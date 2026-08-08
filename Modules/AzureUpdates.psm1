using module .\BaseMessage.psm1
using module .\ConfigurationManager.psm1
using module .\M365ServiceHealthHubDB.psm1
using module .\Logging.psm1
using module .\Services\GraphConnector.psm1
using module .\AuthManager.psm1
using module .\AuthManagerHelper.psm1
using module .\EntityMapping\AzureUpdateEntity.psm1

enum AzureUpdateSource {
    Database = 0;
    API = 1;
}

class AzureResourceRetirementInfo {
    static [object]$retirementList = [AzureResourceRetirementInfo]::GetAzureServiceRetirementList();
    static [string]$query = [AzureResourceRetirementInfo]::GetAzureImpactedServicesQuery();
    static [object]$impactedServices = [AzureResourceRetirementInfo]::GetImpactedServices();

    static [object]GetAzureServiceRetirementList() {
        $response = Invoke-WebRequest -Uri "https://afd.hosting.portal.azure.net/appinsights/content/1.0.20251218.0209/iframe/node_modules/wb/en-us/Workbooks/Azure%20Advisor-AzureServiceRetirement.json" -UseBasicParsing

        $res = $null;

        if ($response.StatusCode -eq 200) {
            $content = ConvertFrom-Json $response.Content
            $retirementObj = $content.items | Where-Object { $_.content.title -like "Retiring Azure Services*" -and $_.name -eq "Unfiltered Data" } | Select-Object -First 1
            $res = ConvertFrom-Json $(ConvertFrom-Json $retirementObj.content.query).content
        }
        else {
            [TraceLogging]::LogEvent([LoggingLevel]::Error, "AzureUpdates", "AzureResourceRetirementInfo.GetAzureServiceRetirementList()", "aur101", "Failed to retrieve Azure Service Retirement information. HTTP $($response.StatusCode): $($response.StatusDescription)");
        }

        return $res
    }

    static [object]GetAzureImpactedServicesQuery() {
        $response = Invoke-WebRequest -Uri "https://afd.hosting.portal.azure.net/appinsights/content/1.0.20251218.0209/iframe/node_modules/wb/en-us/Workbooks/Azure%20Advisor-AzureServiceRetirement.json" -UseBasicParsing

        $res = $null;

        if ($response.StatusCode -eq 200) {
            $content = ConvertFrom-Json $response.Content
            $queryObj = $content.items | Where-Object { $_.content.resourceType -eq "microsoft.resourcegraph/resources" -and $_.content.parameters.name -eq "BaseQuery" } | Select-Object -First 1
            $res = $queryObj.content.parameters.value
        }
        else {
            [TraceLogging]::LogEvent([LoggingLevel]::Error, "AzureUpdates", "AzureResourceRetirementInfo.GetAzureImpactedServicesQuery()", "aur102", "Failed to retrieve Azure Impacted Services query. HTTP $($response.StatusCode): $($response.StatusDescription)");
        }

        return $res
    }

    static [object]GetImpactedServices() {
        $authMgr = $null;
        $authConfigKey = [ConfigurationManager]::GraphApiAuthConfig;
                            
        if ([string]::IsNullOrWhiteSpace($authConfigKey))
        {
            $authMgr = [AuthManagerHelper]::CreateInstance("https://management.azure.com")
        } else {
            $authConfigJson = [ConfigurationManager]::GetSecret($authConfigKey);
            $authConfig = ConvertFrom-Json $authConfigJson
            $authMgr = [AuthManager]::new(
                $authConfig.ClientId,
                $authConfig.ClientSecret,
                $authConfig.TenantDomain,
                "https://management.azure.com")
        }
        
        $headers = @{Authorization = "Bearer $($authMgr.Token.access_token)"; "Content-Type" = "application/json" }
        $subscriptionListUri = "https://management.azure.com/subscriptions?api-version=2020-01-01" 
        $response = Invoke-WebRequest -Method GET -Uri $subscriptionListUri -Headers $headers -SkipHttpErrorCheck
        $subscriptions = $null;
        if ($response.StatusCode -eq 200) {
            $subscriptions = ConvertFrom-Json $response.Content
        }
        else {
            [TraceLogging]::LogEvent([LoggingLevel]::Error, "AzureUpdates", "AzureResourceRetirementInfo.GetImpactedServices()", "aur103", "Failed to retrieve Azure Subscriptions list. HTTP $($response.StatusCode): $($response.StatusDescription)");
            return $null;
        }
        $subscriptionListJson = ConvertTo-Json $($subscriptions.value | Select-Object -ExpandProperty subscriptionId)
        if (-not $subscriptionListJson.StartsWith('[')) {
            $subscriptionListJson = '[' + $subscriptionListJson + ']'
        }

        $azQuery = [AzureResourceRetirementInfo]::GetAzureImpactedServicesQuery();
        
        $body = '{"query": "' + $azQuery + '","subscriptions":' + $subscriptionListJson + ',"options":{"resultFormat":"table"}}'
        $resourceGraphUri = "https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01"
        $response = Invoke-WebRequest -Method POST -Uri $resourceGraphUri -Headers $headers -Body $body -SkipHttpErrorCheck
        if ($response.StatusCode -eq 200) 
        {
            $impactedServicesRaw = ConvertFrom-Json $response.Content
            $serviceList = [System.Collections.Generic.List[object]]::new()
            foreach ($row in $impactedServicesRaw.data.rows) {
                $obj = New-Object -TypeName PSObject
                $c = 0
                foreach ($value in $row) {
                    $propertyName = ""
                    try {
                        $propertyName = $impactedServicesRaw.data.columns[$c].name
                    }
                    catch {
                        $propertyName = "Property$c"
                    }
                    $obj | Add-Member -NotePropertyName $propertyName -NotePropertyValue $value
                    $c++
                }
                $serviceList.Add($obj)
            }
            return $serviceList
        }
        else {
            [TraceLogging]::LogEvent([LoggingLevel]::Error, "AzureUpdates", "AzureResourceRetirementInfo.GetImpactedServices()", "aur104", "Failed to retrieve Azure Impacted Services. HTTP $($response.StatusCode): $($response.StatusDescription)");
            return $null;
        }
    }
}

class AzureUpdate: BaseMessage {
    hidden [M365ServiceHealthHubDB]$m_m365shhdb = [M365ServiceHealthHubDB]::new();
    hidden [string]$APIMessageJsonCache = [string]::Empty
    hidden [AzureUpdateSource]$serviceCommSource = [AzureUpdateSource]::Database;

    hidden [void] Init(
        [string]$Id,
        [AzureUpdateSource]$Source
    ) {
        $this.Id = $Id;
        $this.serviceCommSource = $Source;
        
        if ($this.serviceCommSource -eq [AzureUpdateSource]::Database) {
            $this.GetAzureUpdateFromDatabase($Id)
        }
        else {
            $this.GetAzureUpdateFromAPI($Id)
        }
    }

    AzureUpdate() {

    }

    AzureUpdate(
        [AzureUpdateSource]$Source
    ) {
        $this.serviceCommSource = $Source;
    }

    AzureUpdate(
        [string]$Id
    ) {
        $this.Init($Id, [AzureUpdateSource]::API);
    }

    AzureUpdate(
        [string]$Id,
        [AzureUpdateSource]$Source
    ) {
        $this.Init($Id, $Source);
    }

    [string]GetAzureUpdateJsonFromAPI(
        [string]$Id
    ) {
        $result = [AzureUpdateHelper]::GetAzureUpdates();

        return $($result | Where-Object Id -eq $Id | ConvertTo-Json -Depth 20)
    }

    [void]GetAzureUpdateFromAPI(
        [string]$Id
    ) {
        $mJson = $this.GetAzureUpdateJsonFromAPI($Id)

        $messageObj = ConvertFrom-Json $mJson
        if ($null -ne $messageObj) {
            $this.MessageJson = ConvertTo-Json $messageObj.value -Depth 5
        }
        else {
            throw "Message is not provided in supported format."
        }

        $this.DeserializeMessage();
        
        if ($null -ne $this.Message.lastModifiedDateTime) {
            $this.LastUpdatedTime = $this.Message.lastModifiedDateTime;
        }
    }

    [void]GetServiceCommunicationFromMemoryObject(
        [System.Object]$Object
    ) {
        $this.Message = $Object
        $this.MessageJson = ConvertTo-Json $Object -Depth 5
        $this.Id = $this.Message.Id

        if ($null -ne $this.Message.published) {
            $apiLastUpdatedDateTime = [DateTime]::new(
                $this.Message.published.Year,
                $this.Message.published.Month,
                $this.Message.published.Day,
                $this.Message.published.Hour,
                $this.Message.published.Minute,
                $this.Message.published.Second
            ); #make sure we ignore miliseconds

            $this.LastUpdatedTimeFromDB = $this.LastUpdatedTime;
            $this.UpdatesAvailable = $apiLastUpdatedDateTime -gt $this.LastUpdatedTime;
            $this.LastUpdatedTime = $apiLastUpdatedDateTime;
        }
    }

    hidden [void]DeserializeMessage() {
        $messageObj = ConvertFrom-Json $this.MessageJson
        if ($null -ne $messageObj -and $null -ne $messageObj.Id) {
            $this.Message = $messageObj
            $this.Id = $this.Message.Id
        }
        else {
            throw "Message is not provided in supported format."
        }
    }

    [void]GetAzureUpdateFromDatabase(
        [string]$Id
    ) {
        $result = $this.m_m365shhdb.GetServiceCommunication($Id, "AZUREUPDATE");
        if ($null -ne $result) {
            $this.ExistsInDatabase = $true;
            $this.Id = $result.ID;
            $this.LastUpdatedTime = $result.LastUpdatedTime;
            $this.MessageJson = $result.Data;
            $this.WorkItemId = $result.WorkItemID;
            $this.WorkItemUrl = $result.WorkItemURL;
            $this.DeserializeMessage();
        }
        else {
            $this.ExistsInDatabase = $false;
        }
    }

    [void]Update() {
        $this.m_m365shhdb.SetServiceCommunication(
            $this.Id,
            $this.LastUpdatedTime,
            $this.MessageJson,
            $this.WorkItemId,
            $this.WorkItemUrl,
            "AZUREUPDATE"
        );

        $this.ExistsInDatabase = $true
    }

    [void]Index() {
        if ($null -eq $global:ServiceHealthHubGraphConnector) {
            $global:ServiceHealthHubGraphConnector = [GraphConnector]::new()

            if ($global:ServiceHealthHubGraphConnector.Enabled) {
                $item = [AzureUpdateEntity]::new($this);

                $indexResult = $global:ServiceHealthHubGraphConnector.IndexItem(
                    $item.m_properties.Id,
                    $item.m_properties.RawData.title,
                    "Azure Updates",
                    $item.m_properties.RawData.summary.Replace([char]0x202f, " ").Replace([char]0x2019, "'").Replace([char]0x201c, '"').Replace([char]0x201d, '"'),
                    [string]::IsNullOrWhiteSpace($item.m_properties.RawData.releaseStatus) ? "Unknown" : $($item.m_properties.RawData.releaseStatus -eq "NOW AVAILABLE" ? "Ready" : "Pending"),
                    [DateTime]::UtcNow.AddYears(2),
                    @(),
                    $null,
                    $null,
                    $item.m_properties.LastUpdatedTime,
                    $item.m_properties.TagsArray,
                    $global:ServiceHealthHubGraphConnector.GetRootUrl() + "/azure/updates?id=$($item.m_properties.Id)",
                    $item.m_properties.Description.Replace([char]0x202f, " ").Replace([char]0x2019, "'").Replace([char]0x201c, '"').Replace([char]0x201d, '"'),
                    "html")
        
                if ($indexResult.Success -eq $false) {
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
                }
                else {
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
}

class AzureUpdateHelper {
    hidden static [M365ServiceHealthHubDB]$m_m365shhdb = [M365ServiceHealthHubDB]::new();
    
    static [string] GetMD5Hash($Message) {
        $md5 = New-Object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider;
        $utf8 = New-Object -TypeName System.Text.UTF8Encoding;
        $Hash = [System.BitConverter]::ToString($md5.ComputeHash($utf8.GetBytes($Message)));
        $Hash = $Hash.Replace("-", "");
        return $Hash
    }

    static [string] GetId($Message) {
        $Hash = [AzureUpdateHelper]::GetMD5Hash($Message)
        return ("AZ-" + $Hash.Substring(0, 4) + '-' + $Hash.Substring(28, 4))
    }

    hidden static [System.Object] GetLastSyncTimeFromDB() {
        return [AzureUpdateHelper]::m_m365shhdb.GetLastSyncTime("AZUREUPDATE");
    }

    static [string] GetEndpoint() {
        return "https://www.microsoft.com/releasecommunications/api/v2/azure";
    }

    static [DateTime] GetLastSyncTime() {
        $val = [AzureUpdateHelper]::GetLastSyncTimeFromDB();

        if (![string]::IsNullOrWhiteSpace($val)) {
            try {
                return [DateTime]::Parse($val)
            }
            catch {
                return [System.Data.SqlTypes.SqlDateTime]::MinValue.Value;
            }
        }
        else {
            return [System.Data.SqlTypes.SqlDateTime]::MinValue.Value;
        }
    }

    static [string] GetLastSyncTimeString() {
        $val = [AzureUpdateHelper]::GetLastSyncTimeFromDB();
             
        if (![string]::IsNullOrWhiteSpace($val)) {
            try {
                return $val + "Z"
            }
            catch {
                return [System.Data.SqlTypes.SqlDateTime]::MinValue.Value.ToString("s") + "Z"
            }
        }
        else {
            return [System.Data.SqlTypes.SqlDateTime]::MinValue.Value.ToString("s") + "Z"
        }
    }

    static [void] SetLastSyncTimestamp() {
        [AzureUpdateHelper]::m_m365shhdb.SetLastSyncTime("AZUREUPDATE");
    }

    static [System.Object[]]GetAzureUpdateList() {
        $uri = [AzureUpdateHelper]::GetEndpoint();

        if (![string]::IsNullOrWhiteSpace($uri)) {
            return [AzureUpdateHelper]::RetrieveAPIData($uri)
        }
        else {
            return @()
        }
    }

    static [System.Object] ConvertAzureUpdateCommunication(
        [System.Object]$Communication
    ) {
        $tags = @()
        foreach ($pc in $Communication.productCategories) {
            $tags += $pc
        }

        foreach ($t in $Communication.tags) {
            $tags += $t
        }

        foreach ($p in $Communication.products) {
            $tags += $p
        }

        $obj = @{
            id                             = $([AzureUpdateHelper]::GetId($Communication.id));
            sourceId                       = $Communication.id;
            title                          = $Communication.title;
            summary                        = "Private preview: $([string]::IsNullOrWhitespace($Communication.privatePreviewAvailabilityDate) ? "none" : $Communication.privatePreviewAvailabilityDate), Public preview: $([string]::IsNullOrWhitespace($Communication.previewAvailabilityDate) ? "none" : $Communication.previewAvailabilityDate), General availability: $([string]::IsNullOrWhitespace($Communication.generalAvailabilityDate) ? "none" : $Communication.generalAvailabilityDate)";
            published                      = [DateTime]$Communication.modified;
            link                           = "https://azure.microsoft.com/updates?id=$($Communication.id)";
            contents                       = $Communication.description;
            releaseStatus                  = $Communication.status;
            tags                           = $tags;
            productCategories              = $Communication.productCategories;
            products                       = $Communication.products;
            generalAvailabilityDate        = $Communication.generalAvailabilityDate;
            previewAvailabilityDate        = $Communication.previewAvailabilityDate;
            privatePreviewAvailabilityDate = $Communication.privatePreviewAvailabilityDate;
            status                         = $Communication.status;
            created                        = $Communication.created;
            modified                       = $Communication.modified;
            availabilities                 = $Communication.availabilities;
            serviceList                    = $Communication.serviceList;
        }

        return $obj;
    }

    static [System.Collections.Generic.List[object]] GetAzureUpdates() {
        $maxRetries = 10;
        $success = $false;
        $retry = 0;
        $list = [System.Collections.Generic.List[object]]::new()

        while ($success -eq $false -and $retry -lt $maxRetries) {
            [TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureUpdates", "AzureUpdatesHelper.GetAzureUpdates()", "auc103", "Retrieving Azure Updates cache. Attempt #$($retry+1) of $maxRetries");

            $uri = [AzureUpdateHelper]::GetEndpoint() + "?`$count=true&includeFacets=true&filter=modified gt 2025-01-01T00:00:00.0000000Z&orderby=modified asc"

            $nextLink = $Uri;
            $data = @()

            do {           
                $result = Invoke-WebRequest -Uri $nextLink -UseBasicParsing

                if ($result.StatusCode -ne 200) {
                    throw "Exception caught: HTTP $($result.StatusCode): $($result.StatusDescription)"
                }
                $commList = ConvertFrom-Json $result.Content

                foreach ($comm in $commList.value) {
                    $data += $comm
                }

                $nextLink = $commList."@odata.nextLink";
            } until ([string]::IsNullOrWhiteSpace($nextLink))

            [TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureUpdates", "AzureUpdatesHelper.GetAzureUpdates()", "auc104", "$($data.Count) Azure Updates retrieved from the API.");

            $list = [System.Collections.Generic.List[object]]::new()

            $impactedServices = [AzureResourceRetirementInfo]::impactedServices
            $retirementInfo = [AzureResourceRetirementInfo]::retirementList
            $pattern = "(?i)(?<=^|[?&])id=([^&#]+)"
            foreach ($comm in $data) {
                $ret = $retirementInfo | Where-Object { [regex]::Match($_.Link, $pattern).Groups[1].Value -eq $comm.id } | Select-Object -First 1
                $services = $impactedServices | Where-Object ServiceId -eq $ret.ID           
                $comm | Add-Member -NotePropertyName "serviceList" -NotePropertyValue $services
                $obj = [AzureUpdateHelper]::ConvertAzureUpdateCommunication($comm)
                $list.Add($obj);
            }
            
            $success = $true;
        }

        [TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureUpdates", "AzureUpdatesHelper.GetAzureUpdates()", "auc105", "Communications processed. $($list.Count) items returned.");
        return $list
    }

    hidden static [System.Object[]] RetrieveAPIData(
        [string]$Uri
    ) {
        $data = @()

        $commList = [AzureUpdateHelper]::GetAzureUpdates();

        foreach ($comm in $commList) {
            $data += $comm
        }

        return $data
    }

    static [System.Object[]]GetAzureUpdateListFromDB(
        [System.Object[]]$CommunicationList
    ) {
        $commList = @()

        $idList = "'" + $($($CommunicationList | Select-Object -ExpandProperty id) -join "','") + "'";

        if (![string]::IsNullOrWhiteSpace($idList)) {
            $result = [AzureUpdateHelper]::m_m365shhdb.GetServiceCommunicationCollection(
                $idList,
                "AZUREUPDATE"
            );

            foreach ($resultItem in $result.Rows) {              
                $item = [AzureUpdate]::new(); 
                $item.ExistsInDatabase = $true;
                $item.Id = $resultItem.ID;
                $item.LastUpdatedTime = $resultItem.LastUpdatedTime;
                $item.MessageJson = $resultItem.Data;
                $item.WorkItemId = $resultItem.WorkItemID;
                $item.WorkItemUrl = $resultItem.WorkItemURL;
                $item.DeserializeMessage();

                $commList += $item
            }   
        }

        return $commList
    }

    static [System.Object[]]GetAzureUpdateCollection() {
        $result = @()

        $comms = [AzureUpdateHelper]::GetAzureUpdateList();
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureUpdates", "AzureUpdatesHelper.GetAzureUpdateCollection()", "auc120", "$($comms.Count) communications retrieved from API. Checking database for existing items.");

        if ($null -ne $comms -and $comms.Count -gt 0) {
            $dbItems = [AzureUpdateHelper]::GetAzureUpdateListFromDB($comms)
            [TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureUpdates", "AzureUpdatesHelper.GetAzureUpdateCollection()", "auc121", "$($dbItems.Count) communications retrieved from the database. Checking for new items and changes.");

            foreach ($comm in $comms) {
                $dbComm = $dbItems | Where-Object Id -eq $comm.Id | Select-Object -First 1
                if ($null -eq $dbComm) {
                    $dbComm = [AzureUpdate]::new();
                    $dbComm.ExistsInDatabase = $false;
                }
                $dbComm.GetServiceCommunicationFromMemoryObject($comm);

                $result += $dbComm
            }
        }

        $filteredResult = $($result | Where-Object UpdatesAvailable -eq $true)
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureUpdates", "AzureUpdatesHelper.GetAzureUpdateCollection()", "auc125", "$($filteredResult.Count) communications for processing found.");
        return $filteredResult
    }
}