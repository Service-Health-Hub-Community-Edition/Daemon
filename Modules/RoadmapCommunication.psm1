using module .\BaseMessage.psm1
using module .\AuthManager.psm1
using module .\ConfigurationManager.psm1
using module .\SqlConnector.psm1
using module .\M365ServiceHealthHubDB.psm1
using module .\Logging.psm1
using module .\Utility.psd1
using module .\Utility.psm1
using module .\Services\GraphConnector.psm1
using module .\EntityMapping\RoadmapEntity.psm1

enum RoadmapCommunicationSource
{
    Database = 0;
    API = 1;
}

class RoadmapCacheItem
{
    [string]$Id
    [string]$Link
    [System.Object]$Tags
    [System.Object]$Products
    [System.Object]$CloudInstances
    [System.Object]$ReleasePhase
    [System.Object]$Platforms
    [string]$Title
    [string]$Description
    [string]$Status
    [string]$MoreInfoLink
    [datetime]$Published
    [datetime]$LastUpdated
    [string]$AvailabilityDate
    [datetime]$AvailabilityDateFrom
    [datetime]$AvailabilityDateTo
    [string]$PublicPreviewDate
    [datetime]$PublicPreviewDateFrom
    [datetime]$PublicPreviewDateTo

    RoadmapCacheItem()
    {

    }
}

class RoadmapCache
{
    [System.Object[]]$RoadmapItems = $null;

    RoadmapCache()
    {
        $this.RefreshCache()
    }

    hidden [System.Object] GetDateRange(
        [string]$dateString
    )
    {           
        $availabilityDateFrom = [datetime]::MinValue
        $availabilityDateTo = [datetime]::MaxValue

        if (![string]::IsNullOrWhiteSpace($dateString))
        {
            if ($dateString.StartsWith("Q"))
            {
                $quarter = [int]$([string]$($dateString[1])) - 1
                $year = [int]$($dateString.Substring(3))
                $startMonth = $quarter * 3 + 1
                $endMonth = $startMonth + 2
                # Write-Host "Availability date match: $dateString, Quarter: $quarter, Start Month: $startMonth, End Month: $endMonth"
                $daysInLastMonth = [datetime]::DaysInMonth($year, $endMonth)
                $availabilityDateFrom = [datetime]::new($year,$startMonth, 1, 0, 0, 0, [System.DateTimeKind]::Utc)
                $availabilityDateTo = [datetime]::new($year,$endMonth, $daysInLastMonth, 23, 59, 59, [System.DateTimeKind]::Utc)  
            }
            else {
                $availabilityDateFrom = [datetime]$dateString
                $daysInMonth = [datetime]::DaysInMonth($availabilityDateFrom.Year,$availabilityDateFrom.Month)
                $availabilityDateTo = [datetime]::new($availabilityDateFrom.Year,$availabilityDateFrom.Month, $daysInMonth, 23, 59, 59, [System.DateTimeKind]::Utc)
            }
        }

        $result = @{
            From = $availabilityDateFrom;
            To = $availabilityDateTo;
        }

        return $result
    }

    [void]RefreshCache()
    {
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "Roadmap", "Cache", "rmc574", "Refreshing roadmap cache");
			
        $this.RoadmapItems = @()

        [TraceLogging]::LogEvent([LoggingLevel]::Information, "Roadmap", "Cache", "rmc575", "Retrieving roadmap items");
        $roadmapContent = Invoke-RestMethod -Method Get -Uri "https://www.microsoft.com/releasecommunications/api/v1/m365"
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "Roadmap", "Cache", "rmc576", "$($roadmapContent.Count) items retrieved. Populating cache.");

        foreach ($rssItem in $roadmapContent)
        {
            try {
                $item = [RoadmapCacheItem]::new()
                $item.Id = $rssItem.id
                $item.Link = [string]::Format("https://www.microsoft.com/en-us/microsoft-365/roadmap?searchterms={0}", $rssItem.id)
                $item.Tags = $rssItem.tags
                $item.Products = $rssItem.tagsContainer.products
                $item.CloudInstances = $rssItem.tagsContainer.cloudInstances
                $item.ReleasePhase = $rssItem.tagsContainer.releasePhase
                $item.Platforms = $rssItem.tagsContainer.platforms
                $item.Title = $rssItem.title
                $item.Description = $rssItem.description
                $item.Status = $rssItem.status
                $item.MoreInfoLink = $rssItem.moreInfoLink
                $item.Published = $([datetime]$($rssItem.created))
                $item.LastUpdated = $([datetime]$($rssItem.modified))
                $item.AvailabilityDate = [string]::IsNullOrWhiteSpace($rssItem.publicDisclosureAvailabilityDate) ? "" : $rssItem.publicDisclosureAvailabilityDate.Replace("CY","", [System.StringComparison]::InvariantCultureIgnoreCase)
                $item.PublicPreviewDate = [string]::IsNullOrWhiteSpace($rssItem.publicPreviewDate) ? "" : $rssItem.publicPreviewDate.Replace("CY","", [System.StringComparison]::InvariantCultureIgnoreCase)

                $availabilityDateRange = $this.GetDateRange($item.AvailabilityDate);
                $item.AvailabilityDateFrom = $availabilityDateRange.From;
                $item.AvailabilityDateTo = $availabilityDateRange.To;

                $availabilityDateRange = $this.GetDateRange($item.PublicPreviewDate);
                $item.PublicPreviewDateFrom = $availabilityDateRange.From;
                $item.PublicPreviewDateTo = $availabilityDateRange.To;

                $this.RoadmapItems += $item
            }
            catch {
                [TraceLogging]::LogEvent([LoggingLevel]::Error, "Roadmap", "Cache", "rmc591", "An exception caught while processing roadmap item [$($rssItem.guid.'#text')] $($rssItem.title). Exception: $($_.Exception) $($_.InvocationInfo.PositionMessage)");
            }
            
        }

        [TraceLogging]::LogEvent([LoggingLevel]::Information, "Roadmap", "Cache", "rmc599", "Cache populated.");
    }

    [System.Object]GetRoadmapItem([string]$Id)
    {
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "Roadmap", "Cache", "rmc615", "Retrieving roadmap item $Id from the roadmap cache.");
        if ($null -eq $this.RoadmapItems)
        {
            $this.RefreshCache()
        }

        return $this.RoadmapItems | Where-Object Id -eq $Id | Sort-Object LastUpdated -Descending | Select-Object -First 1
    }

    [System.Object]GetRoadmapItems([datetime]$LastUpdatedTime)
    {
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "Roadmap", "Cache", "rmc725", "Retrieving all roadmap items updated since $LastUpdatedTime from the roadmap cache.");
        if ($null -eq $this.RoadmapItems)
        {
            $this.RefreshCache()
        }

        $items = $this.RoadmapItems | Where-Object LastUpdated -ge $LastUpdatedTime
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "Roadmap", "Cache", "rmc726", "$($items.Count) items found.");
        
        return $items
    }
}

class RoadmapCommunication: BaseMessage
{
    hidden [M365ServiceHealthHubDB]$m_m365shhdb = [M365ServiceHealthHubDB]::new();
    [bool]$UpdatesAvailable = $false;

    RoadmapCommunication()
    {

    }

    RoadmapCommunication(
        [string]$Id,
        [RoadmapCommunicationSource]$Source
    )
    {
        if ($Source -eq [RoadmapCommunicationSource]::Database)
        {
            $this.GetRoadmapCommunicationFromDatabase($Id)
        }
        else {
            $this.GetRoadmapCommunicationFromAPI($Id)
        }
    }

    RoadmapCommunication(
        [string]$Id
    )
    {
        $this.GetRoadmapCommunicationFromDatabase($Id)
    }

    [void]GetRoadmapCommunicationFromDatabase(
        [string]$Id
    )
    {
        $result = $this.m_m365shhdb.GetServiceCommunication($Id, "ROADMAPCOMMUNICATION");
        
        if ($null -ne $result -and $result.Rows.Count -gt 0) {
            $row = $result.Rows | Select-Object -First 1
            $this.ExistsInDatabase = $true;
            $this.Id = $row.ID;
            $this.LastUpdatedTime = $row.LastUpdatedTime;
            $this.MessageJson = $row.Data;
            $this.WorkItemId = $row.WorkItemID;
            $this.WorkItemUrl = $row.WorkItemURL;
            $this.Indexed = $row.Indexed;
            $this.DeserializeMessage();
        }
        else {
            $this.ExistsInDatabase = $false;
        }
    }

    [void]GetNewestVersionFromAPI()
    {
        if (![string]::IsNullOrWhiteSpace($this.Id))
        {
            $this.GetRoadmapCommunicationFromAPI($this.Id);
        }
    }

    [void]GetRoadmapCommunicationFromAPI(
        [string]$Id
    )
    {
        if ($null -eq $Global:RoadmapCache)
        {
            $Global:RoadmapCache = [RoadmapCache]::new()
        }

        $messageObj = $Global:RoadmapCache.GetRoadmapItem($Id)
        $this.MessageJson = ConvertTo-Json $messageObj -Depth 5

        $this.DeserializeMessage();
        
        if ($null -ne $this.Message.LastUpdated){
            $this.LastUpdatedTime = $this.Message.LastUpdated;
        }
    }

    hidden [bool]CommunicationUpdateAvailable(
        [System.Object]$OldMessage,
        [System.Object]$NewMessage
    )
    {
        if (($null -eq $OldMessage) -and ($null -ne $NewMessage))
        {
            return $true
        }

        return $(($NewMessage.LastUpdated -gt $OldMessage.LastUpdated) -or 
                 ($NewMessage.Title -ne $OldMessage.Title) -or
                 ($NewMessage.Description -ne $OldMessage.Description) -or
                 ($NewMessage.Link -ne $OldMessage.Link) -or
                 ($NewMessage.Published -ne $OldMessage.Published) -or
                 ($NewMessage.AvailabilityDate -ne $OldMessage.AvailabilityDate) -or
                 ![Utility]::ObjectsEqual($NewMessage.Category, $OldMessage.Category)                 )
    }

    hidden [void]DeserializeMessage()
    {
        $messageObj = ConvertFrom-Json $this.MessageJson
        $this.UpdatesAvailable = $this.CommunicationUpdateAvailable($this.Message, $messageObj)

        if ($null -ne $messageObj -and $null -ne $messageObj.Id) {
            $this.Message = $messageObj
            $this.Id = $this.Message.Id
        }
        else {
            throw "Message is not provided in supported format."
        }
    }

    [void]Update()
    {
        $this.m_m365shhdb.SetServiceCommunication(
            $this.Id,
            $this.LastUpdatedTime,
            $this.MessageJson,
            $this.WorkItemId,
            $this.WorkItemUrl,
            "ROADMAPCOMMUNICATION"
        );

        $this.ExistsInDatabase = $true
    }

    [void]Index()
    {
        if ($null -eq $global:ServiceHealthHubGraphConnector)
        {
            $global:ServiceHealthHubGraphConnector = [GraphConnector]::new()
        }

        if ($global:ServiceHealthHubGraphConnector.Enabled)
        {
            $item = [RoadmapEntity]::new($this);

            $indexResult = $global:ServiceHealthHubGraphConnector.IndexItem(
                $item.m_properties.Id,
                $item.m_properties.RawData.Title,
                "Microsoft 365 Roadmap",
                $item.m_properties.Description.Replace([char]0x202f, " ").Replace([char]0x2019, "'").Replace([char]0x201c, '"').Replace([char]0x201d, '"'),
                $($item.m_properties.RawData.AvailabilityDateTo -gt [DateTime]::UtcNow ? "Active" : "Closed"),
                $item.m_properties.RawData.AvailabilityDateTo ? $item.m_properties.RawData.AvailabilityDateTo.AddMonths(2) : [DateTime]::UtcNow.AddYears(2),
                @($item.m_properties.Service),
                $item.m_properties.RawData.AvailabilityDateFrom,
                $item.m_properties.RawData.AvailabilityDateTo,
                $item.m_properties.RawData.LastUpdated,
                $item.m_properties.CategoryArray,
                $global:ServiceHealthHubGraphConnector.GetRootUrl() + "/roadmap?id=$($item.m_properties.Id)",
                $item.m_properties.IndexItem.Replace([char]0x202f, " ").Replace([char]0x2019, "'").Replace([char]0x201c, '"').Replace([char]0x201d, '"'),
                "html")
    
            if ($indexResult.Success -eq $false)
            {
                $component = $this.GetType().Name
                $componentId = $($this.m_m365shhdb.GetComponents().Rows | Where-Object InternalName -eq $component).ComponentId

                $this.m_m365shhdb.AddActivityLogRecord(
                    [Guid]::Empty,
                    [TraceLogging]::CorrelationID,
                    '',
                    'app-' + [ConfigurationManager]::ClientId + '@' + [ConfigurationManager]::TenantDomain,
                    'IndexFailed',
                    'item://' + $component + '/' + $this.Id,
                    'Item',
                    [Guid]::Empty,
                    $this.Id,
                    $component,
                    $componentId,
                    $indexResult,
                    $null
                );
            } else {
                # push index success event to audit log
                $component = $this.GetType().Name
                $componentId = $($this.m_m365shhdb.GetComponents().Rows | Where-Object InternalName -eq $component).ComponentId

                $this.m_m365shhdb.AddActivityLogRecord(
                    [Guid]::Empty,
                    [TraceLogging]::CorrelationID,
                    '',
                    'app-' + [ConfigurationManager]::ClientId + '@' + [ConfigurationManager]::TenantDomain,
                    'IndexSuccess',
                    'item://' + $component + '/' + $this.Id,
                    'Item',
                    [Guid]::Empty,
                    $this.Id,
                    $component,
                    $componentId,
                    $indexResult,
                    $null
                );
            }
        }    
    }
}

class RoadmapCommunicationHelper
{
    hidden static [M365ServiceHealthHubDB]$m_m365shhdb = [M365ServiceHealthHubDB]::new();
    
    hidden static [System.Object] GetLastSyncTimeFromDB()
    {
        return [RoadmapCommunicationHelper]::m_m365shhdb.GetLastRoadmapSyncTime();
    }

    static [DateTime] GetLastSyncTime()
    {
        $rehydrateRoadmapItems = [Utility]::ParseBooleanValue([ConfigurationManager]::RehydrateRoadmapItems);

        if ($rehydrateRoadmapItems) {
            return [System.Data.SqlTypes.SqlDateTime]::MinValue.Value
        }
        else {
            $val = [RoadmapCommunicationHelper]::GetLastSyncTimeFromDB();

            if (![string]::IsNullOrWhiteSpace($val))
            {
                try
                {
                    return [DateTime]::Parse($val)
                }
                catch
                {
                    return [DateTime]::UtcNow.AddDays(-7)         
                }
            }
            else
            {
               return [DateTime]::UtcNow.AddDays(-7)
            }
        }
    }

    static [string] GetLastSyncTimeString()
    {
        $val = [RoadmapCommunicationHelper]::GetLastSyncTimeFromDB();
             
        if (![string]::IsNullOrWhiteSpace($val))
        {
            try
            {
                return $val+"Z"
            }
            catch
            {
                return [System.Data.SqlTypes.SqlDateTime]::MinValue.Value.ToString("s")+"Z"
            }
        }
        else
        {
            return [System.Data.SqlTypes.SqlDateTime]::MinValue.Value.ToString("s")+"Z"
        }
    }

    static [void] SetLastSyncTimestamp()
    {
        [RoadmapCommunicationHelper]::m_m365shhdb.SetLastRoadmapSyncTime();
    }
}