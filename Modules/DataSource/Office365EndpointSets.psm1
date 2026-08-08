using module ..\Logging.psm1
using module ..\BaseMessage.psm1
using module ..\M365ServiceHealthHubDB.psm1

class Office365EndpointSetChange
{
    [int]$Id
    [int]$EndpointSetId
    [string]$Disposition
    [string]$Impact
    [string]$Version
    [object]$Previous
    [object]$Current
    [object]$Add
    [object]$Remove
    [Office365EndpointSet]$EndpointSet
    [DateTime]$LastModified

    Office365EndpointSetChange() {

    }

    Office365EndpointSetChange(
        [object]$SetChangeObject
    )
    {
        $this.InitializeChangeObject($SetChangeObject);
    }

    Office365EndpointSetChange(
        [object]$SetChangeObject,
        [object]$SetObject
    )
    {
        $this.InitializeChangeObject($SetChangeObject);
        $set = [Office365EndpointSet]::new($SetObject);
        $this.EndpointSet = $set;
    }

    hidden [void] InitializeChangeObject(
        [object]$SetChangeObject
    )
    {
        $this.Id = $setChangeObject.id;
        $this.EndpointSetId = $SetChangeObject.endpointSetId;
        $this.Disposition = $SetChangeObject.disposition;
        $this.Impact = $SetChangeObject.impact;
        $this.Version = $SetChangeObject.version;
        $this.Previous = $SetChangeObject.previous;
        $this.Current = $SetChangeObject.current;
        $this.Add = $SetChangeObject.add;
        $this.Remove = $SetChangeObject.remove;
    }
}

class Office365EndpointSetChanges
{
    hidden static [M365ServiceHealthHubDB]$m_m365shhdb = [M365ServiceHealthHubDB]::new();
    [System.Collections.Generic.List[Office365EndpointSetChange]]$Changes = [System.Collections.Generic.List[Office365EndpointSetChange]]::new();
    
    static [string] GetLastSyncedVersion()
    {
        return [Office365EndpointSetChanges]::m_m365shhdb.GetLatestO365EndpointChangeVersion();
    }

    static [void] SetLastSyncedVersion(
        [string]$Version
    )
    {
        [Office365EndpointSetChanges]::m_m365shhdb.SetLatestO365EndpointChangeVersion($Version);
    }

    static [Office365EndpointSetChanges] GetChanges()
    {
        $result = [Office365EndpointSetChanges]::new();
        $lastSynchronizedVersion = [Office365EndpointSetChanges]::GetLastSyncedVersion();

        if ([string]::IsNullOrWhiteSpace($lastSynchronizedVersion) -or $lastSynchronizedVersion -eq "0000000000")
        {
            [TraceLogging]::LogEvent([LoggingLevel]::Information, "Office365EndpointsChange", "Main", "oec202", "First synchronization detected. Retrieving most recent change set only.");
            $res = Invoke-RestMethod -Method Get -Uri $("https://endpoints.office.com/version?clientrequestid=" + $([Guid]::NewGuid().ToString()))
            $lastSynchronizedVersion = $($res | Where-Object instance -eq Worldwide | Select-Object -First 1).latest

            if ([string]::IsNullOrWhiteSpace($lastSynchronizedVersion))
            {
                $lastSynchronizedVersion = [DateTime]::UtcNow.ToString("yyyyMMdd00");
            }

            return [Office365EndpointSetChanges]::GetChanges($lastSynchronizedVersion, $true);
        } else
        {
            return [Office365EndpointSetChanges]::GetChanges($lastSynchronizedVersion);
        }
    }

    static [Office365EndpointSetChanges] GetChanges(
        [string]$LastSynchronizedVersion
    )
    {
        return [Office365EndpointSetChanges]::GetChanges($LastSynchronizedVersion, $false);
    }

    static [Office365EndpointSetChanges] GetChanges(
        [string]$LastSynchronizedVersion,
        [bool]$IncludeLastSynchronizedVersion = $false
    )
    {
        <# Retrieves all changes since LastSynchronized version.
        Example: 22103100
        #> 

        $result = [Office365EndpointSetChanges]::new();

        [Guid]$RequestId = [Guid]::NewGuid();
        $endpointSetsUri = [string]::Format("https://endpoints.office.com/endpoints/worldwide?clientrequestid={0}", $RequestId);
        $changesUri = [string]::Format("https://endpoints.office.com/changes/worldwide/0000000000?clientrequestid={0}", $RequestId);

        $endpointSetCollection = Invoke-RestMethod -Method GET -Uri $endpointSetsUri
        $changeCollection = Invoke-RestMethod -Method GET -Uri $changesUri

        $changeCollection = $IncludeLastSynchronizedVersion ? 
            $($changeCollection | Where-Object version -ge $LastSynchronizedVersion | Sort-Object endpointSetId) :
            $($changeCollection | Where-Object version -gt $LastSynchronizedVersion | Sort-Object endpointSetId) 

        foreach ($change in $changeCollection)
        {
            $endpointSet = $endpointSetCollection | Where-Object id -eq $change.endpointSetId

            $result.Changes.Add([Office365EndpointSetChange]::new($change, $endpointSet));
        }

        return $result;
    }
}

class Office365EndpointSet
{
    [int]$Id
    [string]$ServiceArea
    [string]$ServiceAreaDisplayName
    [string]$Category
    [bool]$ExpressRoute
    [bool]$Required
    [System.Collections.Generic.List[string]]$IPs
    [System.Collections.Generic.List[string]]$URLs
    [string]$TCPPorts
    [string]$UDPPorts
    [string]$Notes
    [DateTime]$LastModified

    Office365EndpointSet()
    {

    }

    Office365EndpointSet(
        [object]$SetObject
    )
    {
        $this.Id = $SetObject.id;
        $this.ServiceArea = $SetObject.serviceArea;
        $this.ServiceAreaDisplayName = $SetObject.serviceAreaDisplayName;
        $this.Category = $SetObject.category;
        $this.ExpressRoute = $SetObject.expressRoute;
        $this.Required = $SetObject.required;
        $this.IPs = $SetObject.ips ? $SetObject.ips : [System.Collections.Generic.List[string]]::new();
        $this.URLs = $SetObject.urls ? $SetObject.urls : [System.Collections.Generic.List[string]]::new();
        $this.TCPPorts = $SetObject.tcpPorts;
        $this.UDPPorts = $SetObject.udpPorts;
        $this.Notes = $SetObject.notes;
    }
}

class Office365EndpointSets
{
    [System.Collections.Generic.List[Office365EndpointSet]]$EndpointSets = [System.Collections.Generic.List[Office365EndpointSet]]::new();

    Office365EndpointSets()
    {
        $this.Initialize($false);
    }

    Office365EndpointSets(
        [bool]$RetrieveFromDatabase
    )
    {
        $this.Initialize($RetrieveFromDatabase);
    }

    hidden [void] Initialize(
        [bool]$RetrieveFromDatabase
    )
    {
        $this.EndpointSets.Clear();

        if ($RetrieveFromDatabase)
        {
            throw "Not implemented.";
        } else {
            # get the data from the API
            [Guid]$RequestId = [Guid]::NewGuid();
            $endpointSetsUri = [string]::Format("https://endpoints.office.com/endpoints/worldwide?clientrequestid={0}", $RequestId);
            $changesUri = [string]::Format("https://endpoints.office.com/changes/worldwide/0000000000?clientrequestid={0}", $RequestId);

            $sets = Invoke-RestMethod -Method GET -Uri $endpointSetsUri
            $changes = Invoke-RestMethod -Method GET -Uri $changesUri

            foreach ($set in $sets)
            {
                $this.EndpointSets.Add([Office365EndpointSet]::new($set));
            }
        }
    }
}

class Office365EndpointsChange: BaseMessage
{
    hidden [M365ServiceHealthHubDB]$m_m365shhdb = [M365ServiceHealthHubDB]::new();

    Office365EndpointsChange()
    {

    }

    Office365EndpointsChange(
        [string]$Id
    )
    {
        $this.GetServiceCommunicationFromDatabase($Id)
    }

    [void]Set(
        [Office365EndpointSetChange]$Change
    )
    {
        $this.MessageJson = ConvertTo-Json $Change -Depth 10
        $this.GetServiceCommunicationFromDatabase($Change.Id);
        $this.DeserializeMessage();
        $this.UpdatesAvailable = !$this.ExistsInDatabase;
        $this.LastUpdatedTime = [DateTime]::ParseExact($Change.Version.Substring(0, 8), 'yyyyMMdd', $null);
    }

    hidden [void]DeserializeMessage()
    {
        $messageObj = ConvertFrom-Json $this.MessageJson
        if ($null -ne $messageObj.Id) {
            $this.Message = $messageObj
            $this.Id = $messageObj.Id
        }
        else {
            throw "Message is not provided in supported format."
        }
    }

    [void]GetServiceCommunicationFromDatabase(
        [string]$Id
    )
    {
        $result = $this.m_m365shhdb.GetServiceCommunication($Id, "OFFICE365ENDPOINTSCHANGE");
        if ($null -ne $result.Rows -and $result.Rows.Count -gt 0) {
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
            "OFFICE365ENDPOINTSCHANGE"
        );

        $this.ExistsInDatabase = $true
    }
}