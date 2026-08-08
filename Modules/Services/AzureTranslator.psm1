using module ..\ConfigurationManager.psm1
using module ..\M365ServiceHealthHubDB.psm1

class AzureTranslator
{
    hidden [bool]$m_Enabled = [string]::Empty;
    hidden [string]$m_SubscriptionKey = [string]::Empty;
    hidden [string]$m_Region = [string]::Empty;
    hidden [M365ServiceHealthHubDB]$m_m365shhdb = [M365ServiceHealthHubDB]::new();
    
    AzureTranslator()
    {
        $this.m_Enabled = [ConfigurationManager]::GetTranslatorConfigParameter('AzureTranslator.Enabled');
        $this.m_SubscriptionKey = [ConfigurationManager]::GetTranslatorConfigParameter('AzureTranslator.SubscriptionKey');
        $this.m_Region = [ConfigurationManager]::GetTranslatorConfigParameter('AzureTranslator.Region');
    }

    AzureTranslator(
        [string]$SubscriptionKey,
        [string]$Region
    )
    {
        $this.m_SubscriptionKey = $SubscriptionKey;
        $this.m_Region = $Region;
    }

    [System.Object]Translate(
        [string]$Content,
        [string[]]$Languages
    )
    {
        return $this.Translate($Content, $Languages, $false);
    }

    [System.Object]Translate(
        [string]$Content,
        [string[]]$Languages,
        [bool]$Html
    )
    {
        $notFoundInCache = @();
        $result = @{};

        if (!$this.m_Enabled)
        {
            # translator is disabled, return original content
            foreach ($language in $Languages)
            {
                result.Add($language, $Content);
            }
        } else {
            # translator is enabled, translate and return translated content
            foreach ($language in $Languages)
            {
                $cachedTranslation = $this.m_m365shhdb.GetTranslationFromCache($Content, $Language);
                if ($null -eq $cachedTranslation.Rows -or $cachedTranslation.Rows.Count -eq 0)
                {
                    $notFoundInCache += $language;
                }
                else
                {
                    foreach ($translation in $cachedTranslation.Rows)
                    {
                        $result.Add($translation.Language, $translation.Message);
                    }
                }
            }

            if ($notFoundInCache.Count -gt 0)
            {
                # Not found in cache, get translation from the API
                $apiTranslation = $this.GetTranslationFromAPI($Content, $Languages, $Html);
                foreach ($language in $apiTranslation.Keys)
                {
                    $result.Add($language, $apiTranslation[$language]);
                    $this.m_m365shhdb.CacheTranslation($Content, $apiTranslation[$language], $Language);
                }
            }
        }

        return $result
    }

    hidden [System.Object]GetTranslationFromAPI(
        [string]$Content,
        [string[]]$Languages,
        [bool]$Html
    )
    {
        $result = @{};

        if ([string]::IsNullOrWhiteSpace($this.m_SubscriptionKey))
        {
            throw "Azure Translator exception: Subscription key is not specified.";
        }

        if ([string]::IsNullOrWhiteSpace($this.m_Region))
        {
            throw "Azure Translator exception: Region is not specified.";
        }

        $uri = 'https://api.cognitive.microsofttranslator.com/translate?api-version=3.0';

        foreach ($language in $Languages)
        {
            $uri += "&to=$language";
        }

        if ($Html)
        {
            $uri += "&textType=html"
        }

        $body = @{
            Text = $content;
        }

        $headerParams = @{
            "Ocp-Apim-Subscription-Key" = $this.m_SubscriptionKey;
            "Ocp-Apim-Subscription-Region" = $this.m_Region;
        }

        $bodyJson = "[ " + $(ConvertTo-Json $body -Depth 5) + " ]";
        $apiResult = Invoke-RestMethod -Method Post -Uri $uri -Headers $headerParams -Body $bodyJson -ContentType "application/json; charset=utf-8";
        
        foreach ($translation in $apiResult.translations)
        {
            $result.Add($translation.to, $translation.text);
        }

        return $result;
    }
}