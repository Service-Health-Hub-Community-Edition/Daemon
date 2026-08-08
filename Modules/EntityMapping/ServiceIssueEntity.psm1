using module ..\Utility.psd1
using module ..\Utility.psm1
using module ..\Logging.psm1
using module ..\BaseMessage.psm1
using module .\BaseEntity.psm1
using module ..\Services\AzureLanguageServices.psm1

class ServiceIssueEntity: BaseEntity
{
    ServiceIssueEntity(
        [BaseMessage]$Message
    ): base($Message)
    {
        
    }

    [void]Initialize(
        [BaseMessage]$Message
    )
    {
        ([BaseEntity]$this).Initialize($Message);

        if ($null -ne $Message.Message)
        {
            $textSummarization = [TextSummarization]::new();

            $title = [Utility]::NormalizeValue($Message.Message.id) + ": " + 
                    [Utility]::NormalizeValue($Message.Message.title);

            $msg = $Message.Message.posts | Sort-Object createdDateTime -Desc | Select-Object -First 1;
            $description = [regex]::Replace(
                $msg.description.content,
                '^[^:\r\n.]+:', "<b>$&</b>",
                [System.Text.RegularExpressions.RegexOptions]::Multiline).Replace('“','\"').Replace('”','\"').Replace("`r`n", "<br>").Replace("`r", "<br>").Replace("`n", "<br>");

            $history = "<b>Published:</b> " + [Utility]::DateTimeToString($msg.createdDateTime) + "<br/><br/>" + 
                [regex]::Replace(
                    $msg.description.content, 
                    '^[^:\r\n.]+:', "<b>$&</b>",
                    [System.Text.RegularExpressions.RegexOptions]::Multiline).Replace('“','\"').Replace('”','\"').Replace("`r`n", "<br>").Replace("`r", "<br>").Replace("`n", "<br>")
            
            $tags = @();
            if (![string]::IsNullOrWhiteSpace($Message.Message.service))
            {
                $tags += $Message.Message.service;
            }
            
            if (![string]::IsNullOrWhiteSpace($Message.Message.featureGroup))
            {
                $tags += $Message.Message.featureGroup;
            }

            if (![string]::IsNullOrWhiteSpace($Message.Message.feature))
            {
                $tags += $Message.Message.feature;
            }
            
            if (![string]::IsNullOrWhiteSpace($Message.Message.classification))
            {
                $tags += [Utility]::GetTextFromAPICode($Message.Message.classification);
            }

            $nStatus = [string]::IsNullOrWhiteSpace($Message.Message.status) ? "General information" : $Message.Message.status;
            $notificationTitle = [Utility]::GetStatusCode([Utility]::NormalizeValue($nStatus)) +
                                 [Utility]::GetMessageTypeCode('Incident') + " " + $title;

            $impactDescription = [string]::IsNullOrWhiteSpace($Message.Message.impactDescription) ? "Please review the information provided below." : $Message.Message.impactDescription.Trim();
            $notificationStatus = [Utility]::GetTextFromAPICode($Message.Message.status) + " • " + 
                                  [Utility]::GetClassificationCode([Utility]::NormalizeValue($Message.Message.classification)) + " • " +
                                  [Utility]::NormalizeValue($Message.Message.service) + " > " + 
                                  [Utility]::NormalizeValue($Message.Message.featureGroup) + " > " + 
                                  [Utility]::NormalizeValue($Message.Message.feature);

            $summary = $null
            try {
                $summary = $textSummarization.GetSummary($Message.Message.id, [Utility]::ConvertToPlainText($description, $true));
            }
            catch {
                [TraceLogging]::LogEvent([
                    LoggingLevel]::Error, 
                    "ServiceIssueEntity", "Summary", "sie371", "Couldn't process communication summary. Details: $_");
            }

            $indexItem = "<p>Summary: $($summary)</p>"
            $indexItem += "<p>$description</p>"
            $indexItem += "<p>Feature Group: $([Utility]::NormalizeValue($Message.Message.featureGroup))</p>"
            $indexItem += "<p>Feature: $([Utility]::NormalizeValue($Message.Message.feature))</p>"
            $indexItem += "<p>Service: $([Utility]::NormalizeValue($Message.Message.service))</p>"
            $indexItem += "<p>Tags: $($tags -join ', ')</p>"
            $indexItem += "<p>Classification: $([Utility]::GetTextFromAPICode($Message.Message.classification))</p>"
            $indexItem += "<p>Status: $([Utility]::GetTextFromAPICode($Message.Message.status))</p>"
            $indexItem += "<p>Origin: $([Utility]::GetTextFromAPICode($Message.Message.origin))</p>"
            $indexItem += "<p>Resolved: $([Utility]::ParseBooleanValue($Message.Message.isResolved, $false))</p>"
            $indexItem += "<p>Impact Description: $([Utility]::ConvertToPlainText($impactDescription, $true))</p>"
            $indexItem += "<p>Start Time: $([Utility]::DateTimeToString($Message.Message.startDateTime))</p>"
            $indexItem += "<p>End Time: $([Utility]::DateTimeToString($Message.Message.endDateTime))</p>"
            $indexItem += "<p>Last Modified: $([Utility]::DateTimeToString($Message.Message.lastModifiedDateTime))</p>"

            $this.m_properties.Add("OriginalTitle", [Utility]::NormalizeValue($Message.Message.title));
            $this.m_properties.Add("Title", $title);
            $this.m_properties.Add("NotificationTitle", $notificationTitle);
            $this.m_properties.Add("Description", $description);
            $this.m_properties.Add("Summary", $summary);
            $this.m_properties.Add("History", $history);
            $this.m_properties.Add("Service", [Utility]::NormalizeValue($Message.Message.service));
            $this.m_properties.Add("FeatureGroup", [Utility]::NormalizeValue($Message.Message.featureGroup));
            $this.m_properties.Add("Feature", [Utility]::NormalizeValue($Message.Message.feature));
            $this.m_properties.Add("Classification", [Utility]::GetTextFromAPICode($Message.Message.classification));
            $this.m_properties.Add("Status", [Utility]::GetTextFromAPICode($Message.Message.status));
            $this.m_properties.Add("NotificationStatus", $notificationStatus);
            $this.m_properties.Add("Origin", [Utility]::GetTextFromAPICode($Message.Message.origin));
            $this.m_properties.Add("Resolved", [Utility]::ParseBooleanValue($Message.Message.isResolved, $false));
            $this.m_properties.Add("ImpactDescription", $impactDescription);
            $this.m_properties.Add("StartTime", [Utility]::DateTimeToString($Message.Message.startDateTime));
            $this.m_properties.Add("EndTime", [Utility]::DateTimeToString($Message.Message.endDateTime));
            $this.m_properties.Add("LastModified", [Utility]::DateTimeToString($Message.Message.lastModifiedDateTime));
            $this.m_properties.Add("HighImpact", [Utility]::NormalizeValue($Message.Message.highImpact));
            $this.m_properties.Add("TagsArray", $tags);
            $this.m_properties.Add("Tags", $tags -join ";");
            $this.m_properties.Add("IndexItem", $indexItem);
        }
    }

    [DateTime]GetExpirationTime(
        [BaseMessage]$Message
    )
    {
        $endTimeFromMetadata = $Message.Message.endDateTime;
        $endTime = $null -eq $endTimeFromMetadata ? $null : $([DateTime]$endTimeFromMetadata).AddMonths(2);
        if ($null -eq $endTime)
        {
            return ([BaseEntity]$this).GetExpirationTime($Message);
        } else {
            return $endTime;
        }
    }
}