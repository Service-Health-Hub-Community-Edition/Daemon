using module .\BaseMessage.psm1
using module .\ConfigurationManager.psm1
using module .\M365ServiceHealthHubDB.psm1
using module .\Logging.psm1
using module .\Services\GraphConnector.psm1

enum ClientPolicySource
{
    Database = 0;
    API = 1;
}

class ClientPolicy: BaseMessage
{
    hidden [M365ServiceHealthHubDB]$m_m365shhdb = [M365ServiceHealthHubDB]::new();
    hidden [string]$APIMessageJsonCache = [string]::Empty
    hidden [ClientPolicySource]$serviceCommSource = [ClientPolicySource]::Database;

    hidden [void] Init(
        [string]$Id,
        [ClientPolicySource]$Source
    )
    {
        $this.Id = $Id;
        $this.serviceCommSource = $Source;
        
        if ($this.serviceCommSource -eq [ClientPolicySource]::Database)
        {
            $this.GetClientPolicyFromDatabase($Id)
        }
        else {
            $this.GetClientPolicyFromAPI($Id)
        }
    }

    ClientPolicy()
    {

    }

    ClientPolicy(
        [ClientPolicySource]$Source
    )
    {
        $this.serviceCommSource = $Source;
    }

    ClientPolicy(
        [string]$Id
    )
    {
        $this.Init($Id, [ClientPolicySource]::API);
    }

    ClientPolicy(
        [string]$Id,
        [ClientPolicySource]$Source
    )
    {
        $this.Init($Id, $Source);
    }

    [string]GetClientPolicyJsonFromAPI(
        [string]$Id
    )
    {
        $result = [ClientPolicyHelper]::GetClientPolicies();

        return $($result | Where-Object Id -eq $Id | ConvertTo-Json -Depth 20)
    }


    [void]GetClientPolicyFromAPI(
        [string]$Id
    )
    {
        $mJson = $this.GetClientPolicyJsonFromAPI($Id)

        $messageObj = ConvertFrom-Json $mJson
        if ($null -ne $messageObj) {
            $this.MessageJson = ConvertTo-Json $messageObj.value -Depth 5
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

        if ($null -ne $this.Message.published){
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

    [void]GetClientPolicyFromDatabase(
        [string]$Id
    )
    {
        $result = $this.m_m365shhdb.GetServiceCommunication($Id, "ClientPolicy");
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

    [void]Update()
    {
        $this.m_m365shhdb.SetServiceCommunication(
            $this.Id,
            $this.LastUpdatedTime,
            $this.MessageJson,
            $this.WorkItemId,
            $this.WorkItemUrl,
            "ClientPolicy"
        );

        $this.ExistsInDatabase = $true
    }
}

class ClientPolicyHelper
{
    hidden static [M365ServiceHealthHubDB]$m_m365shhdb = [M365ServiceHealthHubDB]::new();
    
    static [string] GetMD5Hash($Message)
    {
        $md5 = New-Object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider;
        $utf8 = New-Object -TypeName System.Text.UTF8Encoding;
        $Hash = [System.BitConverter]::ToString($md5.ComputeHash($utf8.GetBytes($Message)));
        $Hash = $Hash.Replace("-","");
        return $Hash
    }

    static [string] GetId($Message)
    {
        $Hash = [ClientPolicyHelper]::GetMD5Hash($Message)
        return ("CP-" + $Hash.Substring(0,4) + '-' + $Hash.Substring(16, 4) + '-' + $Hash.Substring(28, 4))
    }

    hidden static [System.Object] GetLastSyncTimeFromDB()
    {
        return [ClientPolicyHelper]::m_m365shhdb.GetLastSyncTime("ClientPolicy");
    }

    static [string] GetEndpoint()
    {
        return "https://clients.config.office.net/settings/v1.0/SettingsCatalog/Settings";
    }

    static [DateTime] GetLastSyncTime()
    {
        $val = [ClientPolicyHelper]::GetLastSyncTimeFromDB();

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
        $val = [ClientPolicyHelper]::GetLastSyncTimeFromDB();
             
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
        [ClientPolicyHelper]::m_m365shhdb.SetLastSyncTime("ClientPolicy");
    }

    static [System.Object[]]GetClientPolicyList()
    {
        $uri = [ClientPolicyHelper]::GetEndpoint();

        if (![string]::IsNullOrWhiteSpace($uri))
        {
            return [ClientPolicyHelper]::RetrieveAPIData($uri)
        } else {
            return @()
        }
    }

    static [System.Object] ConvertClientPolicyCommunication(
        [System.Object]$Communication
    )
    {
        $tags = @()
        $supportedPlatforms = @()

        foreach ($t in $Communication.tags)
        {
            $tags += $t
        }

        foreach ($p in $Communication.supportedPlatforms)
        {
            $supportedPlatforms += $p
        }

        $obj = @{
            id = $([ClientPolicyHelper]::GetId($Communication.id));
            sourceId = $Communication.id;
            title = $Communication.displayName;
            defaultValue = $Communication.defaultValue;
            description = $Communication.description;
            firstOfficeVersion = $Communication.firstOfficeVersion;
            lastOfficeVersion = $Communication.lastOfficeVersion;
            tags = $tags;
            supportedPlatforms = $Communication.supportedPlatforms;
            possibleValues = $Communication.settingType;
            agentInstructions = $Communication.agentInstructions;
            lastUpdatedTime = [DateTime]::UtcNow;
        }

        return $obj;
    }

    static [System.Collections.Generic.List[object]] GetClientPolicies()
    {
        $maxRetries = 10;
        $success = $false;
        $retry = 0;
        $list = [System.Collections.Generic.List[object]]::new()

        while ($success -eq $false -and $retry -lt $maxRetries)
        {
            [TraceLogging]::LogEvent([LoggingLevel]::Information, "ClientPolicy", "ClientPolicyHelper.GetClientPolicyies()", "cp103", "Retrieving client policies. Attempt #$($retry+1) of $maxRetries");

            $uri = [ClientPolicyHelper]::GetEndpoint()+"?tag=Cloud+Policies+Composite"

            $nextLink = $Uri;
            $data = @()

            do {           
                $result = Invoke-WebRequest -Uri $nextLink -UseBasicParsing

                if ($result.StatusCode -ne 200)
                {
                    throw "Exception caught: HTTP $($result.StatusCode): $($result.StatusDescription)"
                }
                $commList = ConvertFrom-Json $result.Content

                foreach ($comm in $commList)
                {
                    $data += $comm
                }

                $nextLink = $commList."@odata.nextLink";
            } until ([string]::IsNullOrWhiteSpace($nextLink))

            [TraceLogging]::LogEvent([LoggingLevel]::Information, "ClientPolicy", "ClientPolicyHelper.GetClientPolicies()", "cp104", "$($data.Count) client " + $($data.Count -eq 1 ? "policy" : "policies") + " retrieved from the API.");

            $list = [System.Collections.Generic.List[object]]::new()

            foreach ($comm in $data)
            {
                $obj = [ClientPolicyHelper]::ConvertClientPolicyCommunication($comm)
                $list.Add($obj);
            }
            
            $success = $true;
        }

        [TraceLogging]::LogEvent([LoggingLevel]::Information, "ClientPolicy", "ClientPolicyHelper.GetClientPolicies()", "cp105", "Communications processed. $($list.Count) items returned.");
        return $list
    }

    hidden static [System.Object[]] RetrieveAPIData(
        [string]$Uri
    )
    {
        $data = @()

        $commList = [ClientPolicyHelper]::GetClientPolicies();

        foreach ($comm in $commList)
        {
            $data += $comm
        }

        return $data
    }

    static [System.Object[]]GetClientPolicyListFromDB()
    {
        $commList = @()

        $result = [ClientPolicyHelper]::m_m365shhdb.GetServiceCommunicationCollection("ClientPolicy");

        foreach ($resultItem in $result.Rows)
        {              
            $item = [ClientPolicy]::new(); 
            $item.ExistsInDatabase = $true;
            $item.Id = $resultItem.ID;
            $item.LastUpdatedTime = $resultItem.LastUpdatedTime;
            $item.MessageJson = $resultItem.Data;
            $item.WorkItemId = $resultItem.WorkItemID;
            $item.WorkItemUrl = $resultItem.WorkItemURL;
            $item.DeserializeMessage();

            $commList += $item
        }   

        return $commList
    }

    static [System.Object[]]GetClientPolicyCollection()
    {
        $result = @()

        $comms = [ClientPolicyHelper]::GetClientPolicyList();
        $dbItems = [ClientPolicyHelper]::GetClientPolicyListFromDB()

        $diff = Compare-Object -ReferenceObject $dbItems -DifferenceObject $comms -Property ID -PassThru | Where-Object { $_.SideIndicator -ne '==' }

        [TraceLogging]::LogEvent([LoggingLevel]::Information, "ClientPolicy", "ClientPolicyHelper.GetClientPolicyCollection()", "cp120", "$($diff.Count) changes detected.");

        if ($null -ne $diff -and $diff.Count -gt 0)
        {
            
            [TraceLogging]::LogEvent([LoggingLevel]::Information, "ClientPolicy", "ClientPolicyHelper.GetClientPolicyCollection()", "cp121", "$($dbItems.Count) communications retrieved from the database. Checking for new items and changes.");

            foreach ($comm in $diff)
            {
                $dbComm = $dbItems | Where-Object Id -eq $comm.Id | Select-Object -First 1
                if ($null -eq $dbComm)
                {
                    $dbComm = [ClientPolicy]::new();
                    $dbComm.ExistsInDatabase = $false;
                }
                $dbComm.GetServiceCommunicationFromMemoryObject($comm);

                $result += $dbComm
            }
        }

        [TraceLogging]::LogEvent([LoggingLevel]::Information, "ClientPolicy", "ClientPolicyHelper.GetClientPolicyCollection()", "cp125", "$($result.Count) communications for processing found.");
        return $result
    }
}