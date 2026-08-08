using module ..\ConfigurationManager.psm1
using module ..\M365ServiceHealthHubDB.psm1
using module ..\Utility.psd1
using module ..\Utility.psm1

class TextSummarization
{
    hidden [bool]$m_Enabled = $false;
    hidden [string]$m_Endpoint = [string]::Empty;
    hidden [string]$m_SubscriptionKey = [string]::Empty;
    hidden [int]$m_SentenceCount = 3;  
    hidden [M365ServiceHealthHubDB]$m_m365shhdb = [M365ServiceHealthHubDB]::new();
    
    TextSummarization()
    {
        $this.m_Enabled = [Utility]::ParseBooleanValue([ConfigurationManager]::GetTextSummarizationConfigParameter('TextSummarization.Enabled'));
        $this.m_Endpoint = [ConfigurationManager]::GetTextSummarizationConfigParameter('TextSummarization.Endpoint');
        $this.m_SubscriptionKey = [ConfigurationManager]::GetTextSummarizationConfigParameter('TextSummarization.SubscriptionKey');
        $sentenceCount = [ConfigurationManager]::GetTextSummarizationConfigParameter('TextSummarization.SentenceCount');

        if ($sentenceCount -lt 2 -or $sentenceCount -gt 5)
        {
            $this.m_SentenceCount = 3;
        } else {
            $this.m_SentenceCount = $sentenceCount;
        }
    }

    TextSummarization(
        [string]$Endpoint,
        [string]$SubscriptionKey,
        [int]$SentenceCount    
    )
    {
        $this.m_SubscriptionKey = $SubscriptionKey;
        $this.m_Endpoint = $Endpoint;
        $this.m_SentenceCount = $SentenceCount;
        $this.m_Enabled = $true;
    }

    [System.Object]GetSummary(
        [string]$Id,
        [string]$Content
    )
    {
        $result = $null;
        
        $cachedSummary = $this.m_m365shhdb.GetSummaryFromCache($Content);
        if ($null -eq $cachedSummary.Rows -or $cachedSummary.Rows.Count -eq 0)
        {
            $result = $this.ProcessSummarization($Id, $Content);

            if ($null -ne $result)
            {
                $this.m_m365shhdb.CacheSummary($Id, $Content, $(ConvertTo-Json $result -Depth 10));
            }
        }
        else
        {
            $result = $null -eq $cachedSummary.Rows[0]["Summary"] ? $null : $(ConvertFrom-Json $cachedSummary.Rows[0]["Summary"])
        }

        return $result
    }

    [void]SetSummary(
        [string]$Id,
        [string]$Content,
        [object]$Summary
    )
    {
        if ($null -ne $Summary)
        {
            $this.m_m365shhdb.CacheSummary($Id, $Content, $(ConvertTo-Json $Summary -Depth 10));
        }
    }

    hidden [System.Object]ProcessSummarization(
        [string]$Id,
        [string]$Content
    )
    {
        if (!$this.m_Enabled)
        {
            return $null;
        }

        $headers = @{ 
            "Content-Type" = "application/json; charset=UTF-8";
            "Ocp-Apim-Subscription-Key" = $this.m_SubscriptionKey;
        }
        
        $body = @{
            displayName = "SHH Summarization Task";
            analysisInput = @{
            documents = @(
              @{
                id = "1";
                language = "en";
                text = [Utility]::ConvertISO88591ToUTF8($Content);
              }
            )
          };
          tasks = @(
            @{
              kind = "AbstractiveSummarization"; # AbstractiveSummarization
              taskName = "Task for " + $Id;
              parameters = @{
                sentenceCount = $this.m_SentenceCount;
              }
            }
          )
        }
        
        $uri = $this.m_Endpoint + "/language/analyze-text/jobs?api-version=2024-11-01"
        $res = Invoke-WebRequest -Method Post -Uri $uri -Headers $headers -Body $(ConvertTo-Json $body -Depth 10) -ContentType "application/json; charset=UTF-8"
        
        $summarizationJob = $null;

        do {
            $response = Invoke-WebRequest -Method Get -Uri $res.Headers.'operation-location'[0] -Headers $headers
            $summarizationJob = ConvertFrom-Json $response.Content
        
            if ($summarizationJob.tasks.inProgress -gt 0)
            {
                Sleep 0.5
            }
        } while ($summarizationJob.tasks.inProgress -gt 0)
        
        $taskResults = $summarizationJob.tasks.items | Where-Object taskName -eq $("Task for " + $Id)
        $document = $taskResults.results.documents | Where-Object id -eq "1"
        
        return $document.summaries
    }
}