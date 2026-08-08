using module ..\Utility.psd1
using module ..\Utility.psm1
using module ..\Logging.psm1
using module ..\BaseMessage.psm1
using module .\BaseEntity.psm1
using module ..\Services\AzureLanguageServices.psm1

class ClientPolicyEntity: BaseEntity
{
    ClientPolicyEntity(
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

            $tags = [System.Collections.Generic.List[string]]::new();
            
            foreach ($platform in $Message.Message.supportedPlatforms) 
            {
                $tags.Add($platform);    
            }
            
            foreach ($tag in $Message.Message.tags) 
            {
                $tags.Add($tag);    
            }

            $tagsJoined = $tags -join ' • ';

            $this.m_properties.Add("Title", $title);
            $this.m_properties.Add("NotificationTitle", $notificationTitle);
            $this.m_properties.Add("Description", $description);
            $this.m_properties.Add("History", $history);
            $this.m_properties.Add("TagsArray", $tags);
            $this.m_properties.Add("Tags", $tagsJoined);
            $this.m_properties.Add("ADOTags", $($tags -join ';'));
            $this.m_properties.Add("DefaultValue", [Utility]::NormalizeValue($Message.Message.defaultValue));
            $this.m_properties.Add("FirstOfficeVersion", [Utility]::NormalizeValue($Message.Message.firstOfficeVersion));
            $this.m_properties.Add("LastOfficeVersion", [Utility]::NormalizeValue($Message.Message.lastOfficeVersion));
            $this.m_properties.Add("AgentInstructions", $Message.Message.agentInstructions);
            $this.m_properties.Add("PossibleValues", $Message.Message.possibleValues);
            $this.m_properties.Add("PolicyId", $Message.Message.sourceId);
            $this.m_properties.Add("LastModified", [Utility]::DateTimeToString($Message.Message.lastUpdate));
            $this.m_properties.Add("SupportedPlatforms", $Message.Message.supportedPlatforms);
            $this.m_properties.Add("PolicyTags", $Message.Message.tags);
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