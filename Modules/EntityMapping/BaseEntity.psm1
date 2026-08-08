using module ..\Utility.psd1
using module ..\Utility.psm1
using module ..\Logging.psm1
using module ..\BaseMessage.psm1

class BaseEntity
{
    $m_properties = @{}

    BaseEntity()
    {

    }

    BaseEntity(
        [BaseMessage]$Message
    )
    {
        $this.Initialize($Message);
    }

    [void]Initialize(
        [BaseMessage]$Message
    )
    {
        $this.m_properties.Add("Id", $Message.Id);
        $this.m_properties.Add("WorkItemId", $Message.WorkItemId);
        $this.m_properties.Add("WorkItemUrl", $Message.WorkItemUrl);
        $this.m_properties.Add("TaskMarkdownLink", [string]::IsNullOrWhiteSpace($Message.WorkItemId) ? "None" : "[$($Message.WorkItemId)]($($Message.WorkItemUrl))");
        $this.m_properties.Add("LastUpdatedTime", $Message.LastUpdatedTime);
        $this.m_properties.Add("RawData", $Message.Message);
        $this.m_properties.Add("InternalCommunicationType", $Message.GetType().FullName.ToUpper());
        $this.m_properties.Add("ExpirationTime", $this.GetExpirationTime($Message));
    }

    [System.Object]GetProperty(
        [string]$Name
    )
    {
        if ([string]::IsNullOrWhiteSpace($Name))
        {
            return $null
        } else {
            return $this.m_properties[$Name];
        }   
    }

    [string]ConvertToPlainText(
        [string]$Name
    )
    {
        if ([string]::IsNullOrWhiteSpace($Name))
        {
            return $null
        } else {
            return [Utility]::ConvertToPlainText($this.m_properties[$Name]);
        }   
    }

    [DateTime]GetExpirationTime(
        [BaseMessage]$Message
    )
    {
        return [DateTime]::UtcNow.AddYears(2);
    }
}