using module ..\Utility.psd1
using module ..\Utility.psm1
using module ..\Logging.psm1
using module ..\BaseMessage.psm1
using module .\BaseEntity.psm1
using module ..\Services\AzureLanguageServices.psm1

class CommonDataConnectorAlertV1Entity: BaseEntity
{
    CommonDataConnectorAlertV1Entity(
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

            $title = [Utility]::NormalizeValue($Message.Message.title);

            $msg = $Message.Message.description;
            $description = [regex]::Replace($msg, '(?<=<p>)\\[.+?\\](?=</p>)', '<b>$&</b>');
            $history = [regex]::Replace($msg, '(?<=<p>)\\[.+?\\](?=</p>)', '<b>$&</b>');

            $notificationTitle = $title;

            $tags = $Message.Message.tags;
            $tagsJoined = $tags -join ' • ';

            $summary = $null
            try {
                $summary = $textSummarization.GetSummary($Message.Message.id, [Utility]::ConvertToPlainText($description, $true));
            }
            catch {
                [TraceLogging]::LogEvent([
                    LoggingLevel]::Error, 
                    "CommonDataConnectorAlertV1Entity", "Summary", "aze371", "Couldn't process communication summary. Details: $_");
            }            
            
            $this.m_properties.Add("Title", $title);
            $this.m_properties.Add("NotificationTitle", $notificationTitle);
            $this.m_properties.Add("Description", $description);
            $this.m_properties.Add("Summary", $summary);
            $this.m_properties.Add("History", $history);
            $this.m_properties.Add("TagsArray", $tags);
            $this.m_properties.Add("Tags", $tagsJoined);
            $this.m_properties.Add("ADOTags", $($tags -join ';'));
            $this.m_properties.Add("Type", [Utility]::NormalizeValue($Message.Message.type));
            $this.m_properties.Add("Source", [Utility]::NormalizeValue($Message.Message.source));
            $this.m_properties.Add("Status", [Utility]::NormalizeValue($Message.Message.status));
            $this.m_properties.Add("Resource", [Utility]::NormalizeValue($Message.Message.resource));
            $this.m_properties.Add("StartTime", [Utility]::DateTimeToString($Message.Message.startTime));
            $this.m_properties.Add("EndTime", [Utility]::DateTimeToString($Message.Message.endTime));
            $this.m_properties.Add("LastModified", [Utility]::DateTimeToString($Message.Message.lastUpdate));
            $this.m_properties.Add("StartTimeDT", $Message.Message.startTime);
            $this.m_properties.Add("EndTimeDT", $Message.Message.endTime);
            $this.m_properties.Add("LastModifiedDT", $Message.Message.lastUpdate);
            $this.m_properties.Add("AdditionalData", $Message.Message.additionalData);
        }
    }

    [DateTime]GetExpirationTime(
        [BaseMessage]$Message
    )
    {
        $endTimeFromMetadata = $Message.Message.endTime;
        $endTime = $null -eq $endTimeFromMetadata ? $null : $($endTimeFromMetadata -as [DateTime]).AddMonths(2);
        if ($null -eq $endTime)
        {
            return ([BaseEntity]$this).GetExpirationTime();
        } else {
            return $endTime;
        }
    }
}