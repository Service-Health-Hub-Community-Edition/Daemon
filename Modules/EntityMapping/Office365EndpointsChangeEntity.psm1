using module ..\Utility.psd1
using module ..\Utility.psm1
using module ..\Logging.psm1
using module ..\BaseMessage.psm1
using module .\BaseEntity.psm1

class Office365EndpointsChangeEntity: BaseEntity
{
    Office365EndpointsChangeEntity(
        [BaseMessage]$Message
    ): base($Message)
    {
        
    }

    hidden [string] GetChangeSegmentString(
        [string]$Header,
        [string]$EffectiveDate,
        [string[]]$Data
    )
    {
        $result = $null;
        if ($null -ne $Data)
        {
            $segmentTemplate = @"
<b>{0}{1}:</b><br/>
{2}<br/><br/>
"@;
            $dataStr = $Data -join ", ";
            $result = [string]::Format($segmentTemplate,
                $Header,
                $([string]::IsNullOrWhiteSpace($EffectiveDate) ?
                    "" : " (effective date: " + [DateTime]::ParseExact($EffectiveDate, 'yyyyMMdd', $null) + ")"),
                [string]::IsNullOrWhiteSpace($dataStr) ? "" : $dataStr)
        }

        return $result
    }

    hidden [string] GetConfigurationElement(
        [string]$Header,
        [object]$Data
    )
    {
        if ($null -eq $Data)
        {
            return ""
        } else {
            $value = "";
            if ($Data.GetType().FullName -eq "System.Boolean")
            {
                $value = $Data ? "Yes" : "No"
            } else {
                $value = $Data
            }

            return [string]::Format("{0}: {1}<br/>", $Header, $value);
        }
    }

    hidden [string] GetConfigurationSegment(
        [string]$Header,
        [object]$Data
    )
    {
        $result = "";
        if ($null -ne $Data)
        {
            $result = [string]::Format("<b>{0}:</b><br/>", $Header);
            $result += $this.GetConfigurationElement("Service area", $Data.serviceArea);
            $result += $this.GetConfigurationElement("Category", $Data.category);
            $result += $this.GetConfigurationElement("Express route", $Data.expressRoute);
            $result += $this.GetConfigurationElement("Required", $Data.required);
            $result += $this.GetConfigurationElement("TCP ports", $Data.tcpPorts);
            $result += $this.GetConfigurationElement("UDP ports", $Data.udpPorts);
            $result += $this.GetConfigurationElement("Notes", $Data.notes);
        }

        return $result
    }

    [void]Initialize(
        [BaseMessage]$Message
    )
    {
        ([BaseEntity]$this).Initialize($Message);

        if ($null -ne $Message.Message)
        {
            $title = [Utility]::NormalizeValue($Message.Message.Id).ToString() + ": " + 
                    [Utility]::NormalizeValue($Message.Message.EndpointSet.ServiceAreaDisplayName);
            
            $messageTemplate = @"
Upcoming changes for {0} Endpoint set detected.
<br/><br/>
{1}
{2}
{3}
{4}
{5}
{6}
"@;

            $msg = [string]::Format($messageTemplate,
                $Message.Message.EndpointSet.ServiceAreaDisplayName,
                $this.GetChangeSegmentString("Added IPs", $Message.Message.Add.effectiveDate, $Message.Message.Add.ips),
                $this.GetChangeSegmentString("Added URLs", $Message.Message.Add.effectiveDate, $Message.Message.Add.urls),
                $this.GetChangeSegmentString("Removed IPs", $null, $Message.Message.Remove.ips),
                $this.GetChangeSegmentString("Removed URLs", $null, $Message.Message.Remove.urls),
                $this.GetConfigurationSegment("Previous", $Message.Message.Previous),
                $this.GetConfigurationSegment("Current", $Message.Message.Current)
            );
            
            $description = [regex]::Replace($msg, '(?<=<p>)\\[.+?\\](?=</p>)', '<b>$&</b>');
            $history = [regex]::Replace($msg, '(?<=<p>)\\[.+?\\](?=</p>)', '<b>$&</b>');

            $notificationTitle = $title;

            $tags = @();
            $tags += $Message.Message.EndpointSet.ServiceArea;
            $tags += $Message.Message.Disposition;
            $tags += $($Message.Message.Impact -split ",")
            $tagsJoined = $tags -join ' • ';

            $this.m_properties.Add("Title", $title);
            $this.m_properties.Add("NotificationTitle", $notificationTitle);
            $this.m_properties.Add("Description", $description);
            $this.m_properties.Add("History", $history);
            $this.m_properties.Add("ServiceArea", $Message.Message.EndpointSet.ServiceArea);
            $this.m_properties.Add("ServiceAreaDisplayName", $Message.Message.EndpointSet.ServiceAreaDisplayName);
            $this.m_properties.Add("Disposition", $Message.Message.Disposition);
            $this.m_properties.Add("Impact", $Message.Message.Impact);
            $this.m_properties.Add("Version", $Message.Message.Version);
            $this.m_properties.Add("TagsArray", $tags);
            $this.m_properties.Add("Tags", $tagsJoined);
            $this.m_properties.Add("ADOTags", $($tags -join ';'));
            $this.m_properties.Add("ActionRequiredBy", [Utility]::DateTimeToString($Message.Message.Add.effectiveDate, "o", "yyyyMMdd"));
            $this.m_properties.Add("LastModified", [string]::IsNullOrWhiteSpace($Message.Message.version) ?
                "" : [Utility]::DateTimeToString($Message.Message.version.Substring(0,8), "o", "yyyyMMdd"))
        }
    }
}