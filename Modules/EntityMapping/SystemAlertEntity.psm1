using module ..\Utility.psd1
using module ..\Utility.psm1
using module ..\Logging.psm1
using module ..\BaseMessage.psm1
using module .\BaseEntity.psm1

class SystemAlertEntity: BaseEntity
{
    SystemAlertEntity(
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
            $title = [Utility]::NormalizeValue($Message.Message.title);

            $msg = $Message.Message.description;
            $description = [regex]::Replace($msg, '(?<=<p>)\\[.+?\\](?=</p>)', '<b>$&</b>');

            $notificationTitle = $title;
            
            $this.m_properties.Add("Title", $title);
            $this.m_properties.Add("NotificationTitle", $notificationTitle);
            $this.m_properties.Add("Description", $description);
            $this.m_properties.Add("AlertType", [Utility]::NormalizeValue($Message.Message.Type));
            $this.m_properties.Add("Source", [Utility]::NormalizeValue($Message.Message.Source));
            $this.m_properties.Add("CommunicationID", [Utility]::NormalizeValue($Message.Message.CommunicationID));
            $this.m_properties.Add("CommunicationType", [Utility]::NormalizeValue($Message.Message.CommunicationType));
            $this.m_properties.Add("Timestamp", [Utility]::DateTimeToString($Message.Message.Timestamp));
            $this.m_properties.Add("AdaptiveCardBody", $Message.Message.AdaptiveCardBody)
        }
    }
}