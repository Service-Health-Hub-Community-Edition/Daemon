using module ..\Utility.psd1
using module ..\Utility.psm1
using module ..\Logging.psm1
using module ..\BaseMessage.psm1
using module .\BaseEntity.psm1
using module ..\Services\AzureLanguageServices.psm1

class AzureAWSSupportTicketEntity: BaseEntity
{
    AzureAWSSupportTicketEntity(
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

            $tags = @($Message.Message.source);

            $tagsJoined = $tags -join ' • ';
            
            $this.m_properties.Add("Title", $title);
            $this.m_properties.Add("NotificationTitle", $notificationTitle);
            $this.m_properties.Add("Description", $description);
            $this.m_properties.Add("History", $history);
            $this.m_properties.Add("TagsArray", $tags);
            $this.m_properties.Add("Tags", $tagsJoined);
            $this.m_properties.Add("ADOTags", $($tags -join ';'));
            $this.m_properties.Add("Subscription", [Utility]::NormalizeValue($Message.Message.subscriptionId));
            $this.m_properties.Add("Caller", [Utility]::NormalizeValue($Message.Message.caller));
            $this.m_properties.Add("Source", [Utility]::NormalizeValue($Message.Message.source));
            $this.m_properties.Add("LastModified", [Utility]::DateTimeToString($Message.Message.lastUpdate));
        }
    }
}