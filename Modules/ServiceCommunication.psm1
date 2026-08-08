using module .\BaseMessage.psm1
using module .\AuthManager.psm1
using module .\AuthManagerHelper.psm1
using module .\ConfigurationManager.psm1
using module .\M365ServiceHealthHubDB.psm1
using module .\Services\GraphConnector.psm1
using module .\EntityMapping\ServiceUpdateEntity.psm1
using module .\EntityMapping\ServiceIssueEntity.psm1
using module .\Logging.psm1

enum ServiceCommunicationSource
{
    Database = 0;
    API = 1;
    Graph = 2;
    GraphGccHigh = 3;
    GraphDoD = 4;
    GraphGermany = 5;
    Graph21Vianet = 6;
}

enum ServiceCommunicationType
{
    ServiceHealthIssue = 0;
    ServiceUpdateMessage = 1;
}

class FeatureReleaseState
{
    [Int32]$RoadmapId;
    [string]$Platform;
    [string]$Status;
    [string]$Ring;
    [DateTime]$Updated;

    FeatureReleaseState()
    {

    }
}

class BaseM365ServiceMessage: BaseMessage
{
    hidden [M365ServiceHealthHubDB]$m_m365shhdb = [M365ServiceHealthHubDB]::new();
    hidden [AuthManager]$AuthManager = $null; 
    hidden [string]$APIMessageJsonCache = [string]::Empty
    hidden [ServiceCommunicationSource]$serviceCommSource = [ServiceCommunicationSource]::Database;

    hidden [void] Init(
        [string]$Id,
        [ServiceCommunicationSource]$Source,
        [AuthManager]$AuthManager
    )
    {
        $this.AuthManager = $AuthManager;
        $this.Id = $Id;
        $this.serviceCommSource = $Source;
        
        if ($this.serviceCommSource -eq [ServiceCommunicationSource]::Database)
        {
            $this.GetServiceCommunicationFromDatabase($Id)
        }
        else {
            $this.GetServiceCommunicationFromAPI($Id)
        }
    }

    BaseM365ServiceMessage()
    {

    }

    BaseM365ServiceMessage(
        [ServiceCommunicationSource]$Source
    )
    {
        $this.serviceCommSource = $Source;
    }

    BaseM365ServiceMessage(
        [string]$Id,
        [AuthManager]$AuthManager
    )
    {
        $this.Init($Id, [ServiceCommunicationSource]::Graph, $AuthManager);
    }

    BaseM365ServiceMessage(
        [string]$Id,
        [ServiceCommunicationSource]$Source,
        [AuthManager]$AuthManager
    )
    {
        $this.Init($Id, $Source, $AuthManager);
    }

    [string]GetServiceCommunicationJsonFromAPI(
        [string]$Id,
        [ServiceCommunicationType]$CommunicationType
    )
    {
        $api = [ServiceCommunicationHelper]::GetApiDomain($this.serviceCommSource);

        if ($null -eq $this.AuthManager)
        {
            $authConfigKey = [ConfigurationManager]::GraphApiAuthConfig;
            if ([string]::IsNullOrWhiteSpace($authConfigKey))
            {
                $this.AuthManager = [AuthManagerHelper]::CreateInstance($api);
            } else {
                $authConfigJson = [ConfigurationManager]::GetSecret($authConfigKey);
                $authConfig = ConvertFrom-Json $authConfigJson
                $this.AuthManager = [AuthManager]::new(
                    $authConfig.ClientId,
                    $authConfig.ClientSecret,
                    $authConfig.TenantDomain,
                    $api)
            }
        }

        # Write-Information "Retrieving Office 365 Message Center messages."
	    $headerParams  = @{'Authorization'="$($this.AuthManager.Token.token_type) $($this.AuthManager.Token.access_token)"}
        
        $uri = [string]::Empty;
        if ($CommunicationType -eq [ServiceCommunicationType]::ServiceUpdateMessage)
        {
            $uri = "$api/v1.0/admin/serviceAnnouncement/messages/$($Id)";
        } elseif ($CommunicationType -eq [ServiceCommunicationType]::ServiceHealthIssue) {
            $uri = "$api/v1.0/admin/serviceAnnouncement/issues/$($Id)";   
        } else {
            throw "Unsupported ommunication type $($CommunicationType.ToString())"
        }
        
        $result = Invoke-WebRequest -Headers $headerParams -Uri $uri -UseBasicParsing
        
        if ($result.StatusCode -ne 200)
        {
            throw "Exception caught: HTTP $($result.StatusCode): $($result.StatusDescription)"
        }

        return $result
    }


    [void]GetServiceCommunicationFromAPI(
        [string]$Id
    )
    {
        $mJson = $this.GetServiceCommunicationJsonFromAPI($Id)

        $messageObj = ConvertFrom-Json $mJson
        if ($null -ne $messageObj) {
            $this.MessageJson = ConvertTo-Json $messageObj -Depth 5
        } else {
            throw "Message is not provided in supported format."
        }

        $this.DeserializeMessage();
        
        if ($null -ne $this.Message.lastModifiedDateTime){
            $this.LastUpdatedTime = $this.Message.lastModifiedDateTime;
        }
    }

    [void]GetServiceCommunicationFromMemoryObject(
        [System.Object]$Object
    )
    {
        $this.Message = $Object
        $this.MessageJson = ConvertTo-Json $Object -Depth 5
        $this.Id = $this.Message.Id

        if ($null -ne $this.Message.lastModifiedDateTime){
            $apiLastUpdatedDateTime = [DateTime]::new(
                $this.Message.lastModifiedDateTime.Year,
                $this.Message.lastModifiedDateTime.Month,
                $this.Message.lastModifiedDateTime.Day,
                $this.Message.lastModifiedDateTime.Hour,
                $this.Message.lastModifiedDateTime.Minute,
                $this.Message.lastModifiedDateTime.Second
            ); #make sure we ignore miliseconds

            $this.LastUpdatedTimeFromDB = $this.LastUpdatedTime;
            $this.UpdatesAvailable = $apiLastUpdatedDateTime -gt $this.LastUpdatedTime;
            $this.LastUpdatedTime = $apiLastUpdatedDateTime;
        }
    }

    hidden [void]DeserializeMessage()
    {
        $messageObj = ConvertFrom-Json $this.MessageJson
        if ($null -ne $messageObj -and $null -ne $messageObj.Id) {
            $this.Message = $messageObj
            $this.Id = $this.Message.Id
        }
        else {
            throw "Message is not provided in supported format."
        }
    }

    [void]GetServiceCommunicationFromDatabase(
        [string]$Id,
        [ServiceCommunicationType]$CommunicationType
    )
    {
        $result = $this.m_m365shhdb.GetServiceCommunication($Id, $CommunicationType.ToString().ToUpper().Trim());
        if ($null -ne $result) {
            $this.ExistsInDatabase = $true;
            $this.Id = $result.ID;
            $this.LastUpdatedTime = $result.LastUpdatedTime;
            $this.MessageJson = $result.Data;
            $this.WorkItemId = $result.WorkItemID;
            $this.WorkItemUrl = $result.WorkItemURL;
            $this.Indexed = $null -eq $result.Indexed ? 0 : $result.Indexed;
            $this.DeserializeMessage();
        }
        else {
            $this.ExistsInDatabase = $false;
        }
    }

    [void]Update(
        [ServiceCommunicationType]$CommunicationType
    )
    {
        $this.m_m365shhdb.SetServiceCommunication(
            $this.Id,
            $this.LastUpdatedTime,
            $this.MessageJson,
            $this.WorkItemId,
            $this.WorkItemUrl,
            $CommunicationType.ToString().ToUpper().Trim()
        );

        $this.ExistsInDatabase = $true
    }
}

class ServiceUpdateMessage: BaseM365ServiceMessage
{
    ServiceUpdateMessage()
    {
        
    }

    ServiceUpdateMessage(
        [string]$Id,
        [ServiceCommunicationSource]$Source,
        [AuthManager]$AuthManager
    ): base($Id, $Source, $AuthManager)
    {
        
    }

    ServiceUpdateMessage(
        [ServiceCommunicationSource]$Source
    ): base($Source)
    {
        
    }

    [string]GetServiceCommunicationJsonFromAPI(
        [string]$Id
    )
    {
        return ([BaseM365ServiceMessage]$this).GetServiceCommunicationJsonFromAPI($Id, [ServiceCommunicationType]::ServiceUpdateMessage);
    }

    [void]GetServiceCommunicationFromDatabase(
        [string]$Id
    )
    {
        ([BaseM365ServiceMessage]$this).GetServiceCommunicationFromDatabase($Id, [ServiceCommunicationType]::ServiceUpdateMessage);
    }

    [void]Update()
    {
        ([BaseM365ServiceMessage]$this).Update([ServiceCommunicationType]::ServiceUpdateMessage);
    }

    [void]Index()
    {
        if ($null -eq $global:ServiceHealthHubGraphConnector)
        {
            $global:ServiceHealthHubGraphConnector = [GraphConnector]::new()
        }

        if ($global:ServiceHealthHubGraphConnector.Enabled)
        {
            $item = [ServiceUpdateEntity]::new($this);

            $indexResult = $global:ServiceHealthHubGraphConnector.IndexItem(
                $item.m_properties.Id,
                $item.m_properties.RawData.title.Replace([char]0x202f, " ").Replace([char]0x2019, "'").Replace([char]0x201c, '"').Replace([char]0x201d, '"'),
                "Microsoft 365 Message Center",
                $item.m_properties.Summary.Replace([char]0x202f, " ").Replace([char]0x2019, "'").Replace([char]0x201c, '"').Replace([char]0x201d, '"'),
                $($item.m_properties.ExpirationTime -gt [DateTime]::UtcNow ? "Active" : "Expired"),
                $item.m_properties.ExpirationTime,
                $item.m_properties.ServicesArray,
                $item.m_properties.RawData.startDateTime,
                [string]::IsNullOrWhiteSpace($item.m_properties.RawData.endDateTime) ? [DateTime]::MaxValue : $item.m_properties.RawData.endDateTime,
                $item.m_properties.RawData.lastModifiedDateTime,
                $item.m_properties.TagsArray,
                $global:ServiceHealthHubGraphConnector.GetRootUrl() + "/messages?id=$($item.m_properties.Id)",
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
                    [PSObject]$indexResult,
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

    [void]GetServiceCommunicationFromMemoryObject(
        [System.Object]$Object
    )
    {
        $oldReleaseStates = $this.GetReleaseState();
        ([BaseM365ServiceMessage]$this).GetServiceCommunicationFromMemoryObject($Object);
        $newReleaseStates = $this.GetReleaseState();

        $releaseStateChanged = $false;

        if ($oldReleaseStates.Count -ne $newReleaseStates.Count)
        {
            $releaseStateChanged = $true
        } else {
            foreach ($rs in $newReleaseStates){
                $oldRs = $oldReleaseStates | Where-Object { $_.RoadmapId -eq $rs.RoadmapId -and $_.Platform -eq $rs.Platform }
                if ($null -eq $oldRs -or $rs.Platform -ne $oldRs.Platform -or $rs.Status -ne $oldRs.Status)
                {
                    $releaseStateChanged = $true;
                    break;
                }
            }
        }

        if ($releaseStateChanged)
        {
            $this.UpdatesAvailable = $true
        }
    }

    [string[]]GetRoadmapIds()
    {
        $roadmapIds=@();

        $roadmap = $this.Message.details | Where-Object Name -eq 'RoadmapIds'
        if (![string]::IsNullOrWhiteSpace($roadmap))
        {
            $roadmapIds = $roadmap.value -split ","
        }

        return $roadmapIds;
    }

    [string[]]GetPlatforms()
    {
        $platformsRes=@();
        $platforms=@();

        $platformData = $this.Message.details | Where-Object Name -eq 'Platforms'
        if (![string]::IsNullOrWhiteSpace($platformData))
        {
            $platforms = $platformData.value -split ","
        }

        foreach ($platform in $platforms)
        {
            $platformsRes += $platform.Trim()
        }

        return $platformsRes;
    }

    [FeatureReleaseState[]]GetReleaseState()
    {
        [FeatureReleaseState[]]$res=@();
        $releaseStateInt=$null;

        $releaseData = $this.Message.details | Where-Object Name -eq 'FeatureStatusJson'
        if (![string]::IsNullOrWhiteSpace($releaseData))
        {
            $releaseStateInt = ConvertFrom-Json $releaseData.value.Replace('\"', '"')
        }

        if ($null -ne $releaseStateInt)
        {
            $keys = $releaseStateInt | Get-Member | Where-Object MemberType -eq "NoteProperty" | Select-Object -ExpandProperty Name
            foreach ($key in $keys)
            {
                $stateCollection = $releaseStateInt."$key"
                foreach ($releaseState in $stateCollection)
                {
                    if ($releaseState.Status -ne "FeatureStatusNotSupported")
                    {
                        $rs = [FeatureReleaseState]::new()
                        $rs.RoadmapId = $releaseState.RoadmapId
                        $rs.Platform = $releaseState.Platform
                        $rs.Status = $releaseState.Status -eq "InRollout" ? "Rolling out" : $releaseState.Status
                        if ($releaseState.LastUpdateTime -is [DateTime])
                        {
                            $rs.Updated = $releaseState.LastUpdateTime
                        } else 
                        {
                            $r = [DateTime]::TryParse($releaseState.LastUpdateTime, [ref]$rs.Updated)
                        }
                        $rs.Ring = $releaseState.LatestRing
                        $res += $rs
                    }
                }
            }
        }

        return $res;
    }
}

class ServiceHealthIssue: BaseM365ServiceMessage
{
    ServiceHealthIssue()
    {
        
    }

    ServiceHealthIssue(
        [string]$Id,
        [ServiceCommunicationSource]$Source,
        [AuthManager]$AuthManager
    ): base($Id, $Source, $AuthManager)
    {
        
    }

    ServiceHealthIssue(
        [ServiceCommunicationSource]$Source
    ): base($Source)
    {
        
    }

    [string]GetServiceCommunicationJsonFromAPI(
        [string]$Id
    )
    {
        return ([BaseM365ServiceMessage]$this).GetServiceCommunicationJsonFromAPI($Id, [ServiceCommunicationType]::ServiceHealthIssue);
    }

    [void]GetServiceCommunicationFromDatabase(
        [string]$Id
    )
    {
        ([BaseM365ServiceMessage]$this).GetServiceCommunicationFromDatabase($Id, [ServiceCommunicationType]::ServiceHealthIssue);
    }

    [void]Update()
    {
        ([BaseM365ServiceMessage]$this).Update([ServiceCommunicationType]::ServiceHealthIssue);
    }

    [void]Index()
    {
        if ($null -eq $global:ServiceHealthHubGraphConnector)
        {
            $global:ServiceHealthHubGraphConnector = [GraphConnector]::new()
        }

        if ($global:ServiceHealthHubGraphConnector.Enabled)
        {
            $item = [ServiceIssueEntity]::new($this);

            $indexResult = $global:ServiceHealthHubGraphConnector.IndexItem(
                $item.m_properties.Id,
                $item.m_properties.RawData.title,
                "Microsoft 365 Service Health",
                $item.m_properties.Summary.text,
                $($item.m_properties.RawData.isResolved ? "Active" : "Resolved"),
                $item.m_properties.ExpirationTime,
                @($item.m_properties.Service),
                $item.m_properties.RawData.startDateTime,
                [string]::IsNullOrWhiteSpace($item.m_properties.RawData.endDateTime) ? [DateTime]::MaxValue : $item.m_properties.RawData.endDateTime,
                $item.m_properties.RawData.lastModifiedDateTime,
                $item.m_properties.TagsArray,
                $global:ServiceHealthHubGraphConnector.GetRootUrl() + "/microsoft365/health?id=$($item.m_properties.Id)",
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

    [System.Byte[]]GetPostIncidentReport()
    {
        $api = [ServiceCommunicationHelper]::GetApiDomain($this.serviceCommSource);

        if ($null -eq $this.AuthManager)
        {
            $authConfigKey = [ConfigurationManager]::GraphApiAuthConfig;
            if ([string]::IsNullOrWhiteSpace($authConfigKey))
            {
                $this.AuthManager = [AuthManagerHelper]::CreateInstance($api);
            } else {
                $authConfigJson = [ConfigurationManager]::GetSecret($authConfigKey);
                $authConfig = ConvertFrom-Json $authConfigJson
                $this.AuthManager = [AuthManager]::new(
                    $authConfig.ClientId,
                    $authConfig.ClientSecret,
                    $authConfig.TenantDomain,
                    $api)
            }
        }

        if ([string]::IsNullOrWhiteSpace($this.Id))
        {
            throw "Incident ID is not specified."
        }

        $headerParams  = @{'Authorization'="$($this.AuthManager.Token.token_type) $($this.AuthManager.Token.access_token)"}
        $uri = "$api/v1.0/admin/serviceAnnouncement/issues/$($this.Id)/incidentReport";
        $result = Invoke-WebRequest -Headers $headerParams -Uri $uri -UseBasicParsing -SkipHttpErrorCheck
        if ($result.StatusCode -ge 400)
        {
            throw "HTTP Request failed with following status code: HTTP $($result.StatusCode)";
        }

        return $result.Content; # byte array, use $result.Content | Set-Content <filepath> -AsByteStream to write locally or pass to Add-FileToBlobStorage (rewrite function to use byte array and create a helper class)
        # for download: https://www.henrikmotzkus.de/azure-blob-download-with-aad-authentication/
    }
}

class ServiceCommunicationHelper
{
    hidden static [M365ServiceHealthHubDB]$m_m365shhdb = [M365ServiceHealthHubDB]::new();
    
    hidden static [System.Object] GetLastSyncTimeFromDB(
        [ServiceCommunicationType]$CommunicationType
    )
    {
        return [ServiceCommunicationHelper]::m_m365shhdb.GetLastSyncTime($CommunicationType.ToString().ToUpper().Trim());
    }

    static [string] GetApiDomain(
        [ServiceCommunicationSource]$ServiceCommunicationSource
    )
    {
        $api = "https://graph.microsoft.com";

        switch ($ServiceCommunicationSource)
        {
            [ServiceCommunicationSource]::Graph { $api = "https://graph.microsoft.com"; }
            [ServiceCommunicationSource]::GraphGccHigh { $api = "https://graph.microsoft.us"; }
            [ServiceCommunicationSource]::GraphDoD { $api = "https://dod-graph.microsoft.us"; }
            [ServiceCommunicationSource]::GraphGermany { $api = "https://graph.microsoft.de"; }
            [ServiceCommunicationSource]::Graph21Vianet { $api = "https://microsoftgraph.chinacloudapi.cn"; }
        }
        return $api;
    }

    static [DateTime] GetLastSyncTime(
        [ServiceCommunicationType]$CommunicationType
    )
    {
        $val = [ServiceCommunicationHelper]::GetLastSyncTimeFromDB($CommunicationType);

        if (![string]::IsNullOrWhiteSpace($val))
        {
            try
            {
                return [DateTime]::Parse($val)
            }
            catch
            {
                # return [System.Data.SqlTypes.SqlDateTime]::MinValue.Value
                return [DateTime]::UtcNow.AddDays(-7)
            }
        }
        else
        {
            # return [System.Data.SqlTypes.SqlDateTime]::MinValue.Value
            return [DateTime]::UtcNow.AddDays(-7)
        }
    }

    static [string] GetLastSyncTimeString(
        [ServiceCommunicationType]$CommunicationType
    )
    {
        $val = [ServiceCommunicationHelper]::GetLastSyncTimeFromDB($CommunicationType);
             
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

    static [void] SetLastSyncTimestamp(
        [ServiceCommunicationType]$CommunicationType
    )
    {
        [ServiceCommunicationHelper]::m_m365shhdb.SetLastSyncTime($CommunicationType.ToString().ToUpper().Trim());
    }

    static [System.Object[]]GetServiceCommunicationList(
        [DateTime]$lastSyncTime,
        [ServiceCommunicationType]$CommunicationType
    )
    {
        return [ServiceCommunicationHelper]::GetServiceCommunicationList($lastSyncTime,$CommunicationType,$null)
    }

    static [System.Object[]]GetServiceCommunicationList(
        [DateTime]$lastSyncTime,
        [ServiceCommunicationType]$CommunicationType,
        [AuthManager]$AuthManager
    )
    {
        return [ServiceCommunicationHelper]::GetServiceCommunicationList(
            $lastSyncTime,
            $CommunicationType,
            $AuthManager,
            [ServiceCommunicationSource]::Graph
        )
    }

    static [System.Object[]]GetServiceCommunicationList(
        [DateTime]$lastSyncTime,
        [ServiceCommunicationType]$CommunicationType,
        [AuthManager]$AuthManager,
        [ServiceCommunicationSource]$CommunicationSource
    )
    {
        $api = [ServiceCommunicationHelper]::GetApiDomain($CommunicationSource);

        $authMgr = $AuthManager;
        if ($null -eq $authMgr)
        {
            $authConfigKey = [ConfigurationManager]::GraphApiAuthConfig;
            if ([string]::IsNullOrWhiteSpace($authConfigKey))
            {
                $authMgr = [AuthManagerHelper]::CreateInstance($api);
            } else {
                $authConfigJson = [ConfigurationManager]::GetSecret($authConfigKey);
                $authConfig = ConvertFrom-Json $authConfigJson
                $authMgr = [AuthManager]::new(
                    $authConfig.ClientId,
                    $authConfig.ClientSecret,
                    $authConfig.TenantDomain,
                    $api)
            }
        }

        $filter = "?`$filter=lastModifiedDateTime gt $($lastSyncTime.ToString("s"))Z"
        $uri = [string]::Empty

        if ($CommunicationType -eq [ServiceCommunicationType]::ServiceHealthIssue)
        {	        
            $uri = "$api/v1.0/admin/serviceAnnouncement/issues" + $filter           
        } elseif ($CommunicationType -eq [ServiceCommunicationType]::ServiceUpdateMessage) {
            $uri = "$api/v1.0/admin/serviceAnnouncement/messages" + $filter           
        }

        if (![string]::IsNullOrWhiteSpace($uri))
        {
            return [ServiceCommunicationHelper]::RetrieveAPIData($authMgr, $uri)
        } else {
            return @()
        }
    }

    hidden static [System.Object[]] RetrieveAPIData(
        [AuthManager]$AuthManager,
        [string]$Uri
    )
    {
        $headerParams  = @{'Authorization'="$($AuthManager.Token.token_type) $($AuthManager.Token.access_token)"}
        $nextLink = $Uri;
        $data = @()

        do {           
            $result = Invoke-WebRequest -Headers $headerParams -Uri $nextLink -UseBasicParsing
        
            if ($result.StatusCode -ne 200)
            {
                throw "Exception caught: HTTP $($result.StatusCode): $($result.StatusDescription)"
            }
            $commList = ConvertFrom-Json $result.Content

            foreach ($comm in $commList.value)
            {
                $data += $comm
            }

            $nextLink = $commList."@odata.nextLink";
        } until ([string]::IsNullOrWhiteSpace($nextLink))
        
        return $data
    }

    static [System.Object[]]GetServiceCommunicationListFromDB(
        [System.Object[]]$CommunicationList,
        [ServiceCommunicationType]$CommunicationType,
        [ServiceCommunicationSource]$CommunicationSource
    )
    {
        $commList = @()

        $idList = "'" + $($($CommunicationList | Select-Object -ExpandProperty id) -join "','") + "'";

        if (![string]::IsNullOrWhiteSpace($idList))
        {
            $result = [ServiceCommunicationHelper]::m_m365shhdb.GetServiceCommunicationCollection(
                $idList,
                $CommunicationType.ToString().ToUpper().Trim()
            );
            
            if ($CommunicationType -eq [ServiceCommunicationType]::ServiceHealthIssue)
            {
                foreach ($resultItem in $result.Rows)
                {              
                    $item = [ServiceHealthIssue]::new($CommunicationSource); 
                    $item.ExistsInDatabase = $true;
                    $item.Id = $resultItem.ID;
                    $item.LastUpdatedTime = $resultItem.LastUpdatedTime;
                    $item.MessageJson = $resultItem.Data;
                    $item.WorkItemId = $resultItem.WorkItemID;
                    $item.WorkItemUrl = $resultItem.WorkItemURL;
                    $item.Indexed = $null -eq $resultItem.Indexed ? 0 : $resultItem.Indexed;
                    $item.DeserializeMessage();

                    $commList += $item
                }
            } elseif ($CommunicationType -eq [ServiceCommunicationType]::ServiceUpdateMessage) {
                foreach ($resultItem in $result.Rows)
                {                
                    $item = [ServiceUpdateMessage]::new($CommunicationSource);
                    $item.ExistsInDatabase = $true;
                    $item.Id = $resultItem.ID;
                    $item.LastUpdatedTime = $resultItem.LastUpdatedTime;
                    $item.MessageJson = $resultItem.Data;
                    $item.WorkItemId = $resultItem.WorkItemID;
                    $item.WorkItemUrl = $resultItem.WorkItemURL;
                    $item.Indexed = $null -eq $resultItem.Indexed ? 0 : $resultItem.Indexed;
                    $item.DeserializeMessage();

                    $commList += $item
                }
            }    
        }

        return $commList
    }

    static [System.Object[]]GetServiceCommunicationCollection(
        [DateTime]$lastSyncTime,
        [ServiceCommunicationType]$CommunicationType,
        [ServiceCommunicationSource]$CommunicationSource,
        [AuthManager]$AuthManager
    )
    {
        return [ServiceCommunicationHelper]::GetServiceCommunicationCollection(
            $lastSyncTime,
            $CommunicationType,
            $CommunicationSource,
            $AuthManager,
            $false
        );
    }

    static [System.Object[]]GetServiceCommunicationCollection(
        [DateTime]$lastSyncTime,
        [ServiceCommunicationType]$CommunicationType,
        [ServiceCommunicationSource]$CommunicationSource,
        [AuthManager]$AuthManager,
        [bool]$ReturnAll
    )
    {
        $result = @()

        $comms = [ServiceCommunicationHelper]::GetServiceCommunicationList($lastSyncTime, $CommunicationType, $AuthManager, $CommunicationSource)     
        if ($null -ne $comms -and $comms.Count -gt 0)
        {
            $dbItems = [ServiceCommunicationHelper]::GetServiceCommunicationListFromDB($comms, $CommunicationType, $CommunicationSource)
            foreach ($comm in $comms)
            {
                $dbComm = $dbItems | Where-Object Id -eq $comm.Id | Select-Object -First 1
                if ($null -eq $dbComm)
                {
                    if ($CommunicationType -eq [ServiceCommunicationType]::ServiceHealthIssue)
                    {
                        $dbComm = [ServiceHealthIssue]::new($CommunicationSource);
                    } elseif ($CommunicationType -eq [ServiceCommunicationType]::ServiceUpdateMessage)
                    {
                        $dbComm = [ServiceUpdateMessage]::new($CommunicationSource);
                    } else {
                        $dbComm = [BaseMessage]::new();
                    }
                    $dbComm.ExistsInDatabase = $false;
                }
                $dbComm.GetServiceCommunicationFromMemoryObject($comm);

                $result += $dbComm
            }
        }

        if ($ReturnAll)
        {
            return $result
        }
        else {
            return $($result | Where-Object UpdatesAvailable -eq $true)
        }
    }

    static [System.Object[]]GetServiceCommunicationCollection(
        [DateTime]$lastSyncTime,
        [ServiceCommunicationType]$CommunicationType
    )
    {
        return [ServiceCommunicationHelper]::GetServiceCommunicationCollection($lastSyncTime, $CommunicationType, [ServiceCommunicationSource]::Graph, $null);
    }

    static [System.Object[]]GetServiceCommunicationCollection(
        [DateTime]$lastSyncTime,
        [ServiceCommunicationType]$CommunicationType,
        [AuthManager]$AuthManager
    )
    {
        return [ServiceCommunicationHelper]::GetServiceCommunicationCollection($lastSyncTime, $CommunicationType, [ServiceCommunicationSource]::Graph, $AuthManager);
    }

}