using module ..\Utility.psd1
using module ..\Utility.psm1
using module ..\Logging.psm1
using module ..\BaseMessage.psm1
using module .\BaseEntity.psm1
using module ..\Services\AzureLanguageServices.psm1

class ReleaseMessageEntity: BaseEntity
{
    ReleaseMessageEntity(
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

            $msg = $Message.Message.description;
            $description = [regex]::Replace($msg, '(?<=<p>)\\[.+?\\](?=</p>)', '<b>$&</b>');
            $history = [regex]::Replace($msg, '(?<=<p>)\\[.+?\\](?=</p>)', '<b>$&</b>');

            $summary = $null
            try {
                $summary = $textSummarization.GetSummary($Message.Message.id, [Utility]::ConvertToPlainText($description, $true));
            }
            catch {
                [TraceLogging]::LogEvent([
                    LoggingLevel]::Error, 
                    "ReleaseMessageEntity", "Summary", "rme371", "Couldn't process communication summary. Details: $_");
            }

            $this.m_properties.Add("Title", $title);
            $this.m_properties.Add("NotificationTitle", $title);
            $this.m_properties.Add("Description", $description);
            $this.m_properties.Add("Summary", $summary);
            $this.m_properties.Add("History", $history);
            $this.m_properties.Add("TagsArray", [Utility]::NormalizeValue($Message.Message.tags));
            $this.m_properties.Add("Tags", [Utility]::NormalizeValue($Message.Message.tags) -join ', ');
            $this.m_properties.Add("ReleaseDate", [Utility]::DateTimeToString($Message.Message.releaseDateTime));
            $this.m_properties.Add("ActionRequiredBy", [Utility]::DateTimeToString($Message.Message.actionRequiredByDateTime));
            $this.m_properties.Add("LastModified", [Utility]::DateTimeToString($Message.Message.lastModifiedDateTime));
        }
    }
}