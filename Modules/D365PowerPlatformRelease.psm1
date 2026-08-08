using module .\BaseMessage.psm1
using module .\ConfigurationManager.psm1
using module .\M365ServiceHealthHubDB.psm1
using module .\EntityMapping\D365PowerPlatformReleaseEntity.psm1
using module .\Logging.psm1
using module .\Services\GraphConnector.psm1

enum D365PowerPlatformReleaseSource
{
    Database = 0;
    API = 1;
}

class D365PowerPlatformRelease: BaseMessage
{
    hidden [M365ServiceHealthHubDB]$m_m365shhdb = [M365ServiceHealthHubDB]::new();
    hidden [string]$APIMessageJsonCache = [string]::Empty
    hidden [D365PowerPlatformReleaseSource]$serviceCommSource = [D365PowerPlatformReleaseSource]::Database;

    hidden [void] Init(
        [string]$Id,
        [D365PowerPlatformReleaseSource]$Source
    )
    {
        $this.Id = $Id;
        $this.serviceCommSource = $Source;
        
        if ($this.serviceCommSource -eq [D365PowerPlatformReleaseSource]::Database)
        {
            $this.GetD365PowerPlatformReleaseFromDatabase($Id)
        }
        else {
            $this.GetD365PowerPlatformReleaseFromAPI($Id)
        }
    }

    D365PowerPlatformRelease()
    {

    }

    D365PowerPlatformRelease(
        [D365PowerPlatformReleaseSource]$Source
    )
    {
        $this.serviceCommSource = $Source;
    }

    D365PowerPlatformRelease(
        [string]$Id
    )
    {
        $this.Init($Id, [D365PowerPlatformReleaseSource]::API);
    }

    D365PowerPlatformRelease(
        [string]$Id,
        [D365PowerPlatformReleaseSource]$Source
    )
    {
        $this.Init($Id, $Source);
    }

    [string]GetD365PowerPlatformReleaseJsonFromAPI(
        [string]$Id
    )
    {
        $uri = [D365PowerPlatformReleaseHelper]::GetEndpoint();
        
        $result = @();
        if ([string]::IsNullOrWhiteSpace([ConfigurationManager]::D365PPFilter))
        {
            $result = Invoke-WebRequest -Uri $uri -Method GET -UseBasicParsing
        } else 
        {
            $result = Invoke-WebRequest -Uri $uri -Method POST -Body [ConfigurationManager]::D365PPFilter -ContentType "application/json"
        }
        
        if ($result.StatusCode -ne 200)
        {
            throw "Exception caught: HTTP $($result.StatusCode): $($result.StatusDescription)"
        }

        $result = ConvertFrom-Json $result

        return $($result | Where-Object Id -eq $Id | ConvertTo-Json -Depth 20)
    }


    [void]GetD365PowerPlatformReleaseFromAPI(
        [string]$Id
    )
    {
        $mJson = $this.GetD365PowerPlatformReleaseJsonFromAPI($Id)

        $messageObj = ConvertFrom-Json $mJson
        if ($null -ne $messageObj) {
            $this.MessageJson = ConvertTo-Json $messageObj.value -Depth 5
        } else {
            throw "Message is not provided in supported format."
        }

        $this.DeserializeMessage();
        
        if ($null -ne $this.Message.GitCommitDate){
            $this.LastUpdatedTime = [DateTime]$this.Message.GitCommitDate;
        }
    }

    [void]GetServiceCommunicationFromMemoryObject(
        [System.Object]$Object
    )
    {
        $this.Message = $Object
        $this.MessageJson = ConvertTo-Json $Object -Depth 5
        $this.Id = $this.Message.SnapshotId

        if ($null -ne $this.Message.GitCommitDate){
            $lastUpdate = [DateTime]$this.Message.GitCommitDate;
            $apiLastUpdatedDateTime = [DateTime]::new(
                $lastUpdate.Year,
                $lastUpdate.Month,
                $lastUpdate.Day,
                $lastUpdate.Hour,
                $lastUpdate.Minute,
                $lastUpdate.Second
            ); #make sure we ignore miliseconds

            $this.LastUpdatedTimeFromDB = $this.LastUpdatedTime;
            $this.UpdatesAvailable = $apiLastUpdatedDateTime -gt $this.LastUpdatedTime;
            $this.LastUpdatedTime = $apiLastUpdatedDateTime;
        }
    }

    hidden [void]DeserializeMessage()
    {
        $messageObj = ConvertFrom-Json $this.MessageJson
        if ($null -ne $messageObj -and $null -ne $messageObj.SnapshotId) {
            $this.Message = $messageObj
            $this.Id = $this.Message.SnapshotId
        }
        else {
            throw "Message is not provided in supported format."
        }
    }

    [void]GetD365PowerPlatformReleaseFromDatabase(
        [string]$Id
    )
    {
        $result = $this.m_m365shhdb.GetServiceCommunication($Id, "D365PowerPlatformRelease");
        if ($null -ne $result) {
            $this.ExistsInDatabase = $true;
            $this.Id = $result.ID;
            $this.LastUpdatedTime = $result.LastUpdatedTime;
            $this.LastUpdatedTimeFromDB = $result.LastUpdatedTime;
            $this.MessageJson = $result.Data;
            $this.WorkItemId = $result.WorkItemID;
            $this.WorkItemUrl = $result.WorkItemURL;
            $this.Indexed = $result.Indexed;
            $this.DeserializeMessage();
        }
        else {
            $this.ExistsInDatabase = $false;
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
            "D365PowerPlatformRelease"
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
            $item = [D365PowerPlatformReleaseEntity]::new($this);

            $indexResult = $global:ServiceHealthHubGraphConnector.IndexItem(
                $item.m_properties.Id,
                $item.m_properties.RawData.FeatureName,
                "Dynamics 365 and Power Platform Release Planner",
                $item.m_properties.BusinessValue.Replace([char]0x202f, " ").Replace([char]0x2019, "'").Replace([char]0x201c, '"').Replace([char]0x201d, '"'),
                $($item.m_properties.RawData.GADate -gt [DateTime]::UtcNow ? "Active" : "Closed"),
                $item.m_properties.ExpirationTime,
                @($item.m_properties.Service),
                $item.m_properties.RawData.FirstGitHubPushDate,
                [string]::IsNullOrWhitespace($item.m_properties.RawData.GADate) ? [DateTime]::MaxValue : $item.m_properties.RawData.GADate,
                $item.m_properties.LastUpdatedTime,
                $item.m_properties.TagsArray,
                $global:ServiceHealthHubGraphConnector.GetRootUrl() + "/d365pp?id=$($item.m_properties.Id)",
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

class D365PowerPlatformReleaseHelper
{
    hidden static [M365ServiceHealthHubDB]$m_m365shhdb = [M365ServiceHealthHubDB]::new();
    
    hidden static [System.Object] GetLastSyncTimeFromDB()
    {
        return [D365PowerPlatformReleaseHelper]::m_m365shhdb.GetLastSyncTime("D365PPRelease");
    }

    static [string] GetEndpoint()
    {
        return "https://legacyapi.mycommunicationshub.com/api/D365PP";
    }

    static [DateTime] GetLastSyncTime()
    {
        $val = [D365PowerPlatformReleaseHelper]::GetLastSyncTimeFromDB();

        if (![string]::IsNullOrWhiteSpace($val))
        {
            try
            {
                return [DateTime]::Parse($val)
            }
            catch
            {
                return [System.Data.SqlTypes.SqlDateTime]::MinValue.Value;
            }
        }
        else
        {
            return [System.Data.SqlTypes.SqlDateTime]::MinValue.Value;
        }
    }

    static [string] GetLastSyncTimeString()
    {
        $val = [D365PowerPlatformReleaseHelper]::GetLastSyncTimeFromDB();
             
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
        [D365PowerPlatformReleaseHelper]::m_m365shhdb.SetLastSyncTime("D365PPRelease");
    }

    static [System.Object[]]GetD365PowerPlatformReleaseList()
    {
        $uri = [D365PowerPlatformReleaseHelper]::GetEndpoint();

        if (![string]::IsNullOrWhiteSpace($uri))
        {
            return [D365PowerPlatformReleaseHelper]::RetrieveAPIData($uri)
        } else {
            return @()
        }
    }

    hidden static [System.Object[]] RetrieveAPIData(
        [string]$Uri
    )
    {
        $result = @();
        if ([string]::IsNullOrWhiteSpace([ConfigurationManager]::D365PPFilter))
        {
            $result = Invoke-WebRequest -Uri $uri -Method GET -UseBasicParsing
        } else 
        {
            $result = Invoke-WebRequest -Uri $uri -Method POST -Body $([ConfigurationManager]::D365PPFilter) -ContentType "application/json" -UseBasicParsing
        }
        $data = @()

        if ($result.StatusCode -ne 200)
        {
            throw "Exception caught: HTTP $($result.StatusCode): $($result.StatusDescription)"
        }
        $commList = ConvertFrom-Json $result.Content

        foreach ($comm in $commList)
        {
            $data += $comm
        }

        return $data
    }

    static [System.Object[]]GetD365PowerPlatformReleaseListFromDB(
        [System.Object[]]$CommunicationList
    )
    {
        $commList = @()

        $idList = "'" + $($($CommunicationList | Select-Object -ExpandProperty SnapshotId) -join "','") + "'";

        if (![string]::IsNullOrWhiteSpace($idList))
        {
            $result = [D365PowerPlatformReleaseHelper]::m_m365shhdb.GetServiceCommunicationCollection(
                $idList,
                "D365PowerPlatformRelease"
            );

            foreach ($resultItem in $result.Rows)
            {              
                $item = [D365PowerPlatformRelease]::new(); 
                $item.ExistsInDatabase = $true;
                $item.Id = $resultItem.ID;
                $item.LastUpdatedTime = $resultItem.LastUpdatedTime;
                $item.LastUpdatedTimeFromDB = $resultItem.LastUpdatedTime;
                $item.MessageJson = $resultItem.Data;
                $item.WorkItemId = $resultItem.WorkItemID;
                $item.WorkItemUrl = $resultItem.WorkItemURL;
                $item.Indexed = $resultItem.Indexed;
                $item.DeserializeMessage();

                $commList += $item
            }   
        }

        return $commList
    }

    static [System.Object[]]GetD365PowerPlatformReleaseCollection()
    {
        return [D365PowerPlatformReleaseHelper]::GetD365PowerPlatformReleaseCollection($true)
    }

    static [System.Object[]]GetD365PowerPlatformReleaseCollection(
        [bool]$OnlyUpdates
    )
    {
        $result = @()

        $comms = [D365PowerPlatformReleaseHelper]::GetD365PowerPlatformReleaseList();     
        if ($null -ne $comms -and $comms.Count -gt 0)
        {
            $dbItems = [D365PowerPlatformReleaseHelper]::GetD365PowerPlatformReleaseListFromDB($comms)
            foreach ($comm in $comms)
            {
                $dbComm = $dbItems | Where-Object Id -eq $comm.SnapshotId | Select-Object -First 1
                if ($null -eq $dbComm)
                {
                    $dbComm = [D365PowerPlatformRelease]::new();
                    $dbComm.ExistsInDatabase = $false;
                }
                $dbComm.GetServiceCommunicationFromMemoryObject($comm);

                $result += $dbComm
            }
        }

        return $OnlyUpdates ? $($result | Where-Object UpdatesAvailable -eq $true) : $result
    }
}