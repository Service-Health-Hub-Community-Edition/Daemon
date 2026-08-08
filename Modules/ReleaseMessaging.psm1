using module .\BaseMessage.psm1
using module .\ConfigurationManager.psm1
using module .\M365ServiceHealthHubDB.psm1

enum ReleaseMessageSource
{
    Database = 0;
    API = 1;
}

class ReleaseMessage: BaseMessage
{
    hidden [M365ServiceHealthHubDB]$m_m365shhdb = [M365ServiceHealthHubDB]::new();
    hidden [string]$APIMessageJsonCache = [string]::Empty
    hidden [ReleaseMessageSource]$serviceCommSource = [ReleaseMessageSource]::Database;

    hidden [void] Init(
        [string]$Id,
        [ReleaseMessageSource]$Source
    )
    {
        $this.Id = $Id;
        $this.serviceCommSource = $Source;
        
        if ($this.serviceCommSource -eq [ReleaseMessageSource]::Database)
        {
            $this.GetReleaseMessageFromDatabase($Id)
        }
        else {
            $this.GetReleaseMessageFromAPI($Id)
        }
    }

    ReleaseMessage()
    {

    }

    ReleaseMessage(
        [ReleaseMessageSource]$Source
    )
    {
        $this.serviceCommSource = $Source;
    }

    ReleaseMessage(
        [string]$Id
    )
    {
        $this.Init($Id, [ReleaseMessageSource]::API);
    }

    ReleaseMessage(
        [string]$Id,
        [ReleaseMessageSource]$Source
    )
    {
        $this.Init($Id, $Source);
    }

    [string]GetReleaseMessageJsonFromAPI(
        [string]$Id
    )
    {
        $uri = [ReleaseMessageHelper]::GetEndpoint();

        $uri += "/$Id";
        
        $result = Invoke-WebRequest -Uri $uri -UseBasicParsing
        
        if ($result.StatusCode -ne 200)
        {
            throw "Exception caught: HTTP $($result.StatusCode): $($result.StatusDescription)"
        }

        return $result.Content
    }


    [void]GetReleaseMessageFromAPI(
        [string]$Id
    )
    {
        $mJson = $this.GetReleaseMessageJsonFromAPI($Id)

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

    [void]GetReleaseMessageFromDatabase(
        [string]$Id
    )
    {
        $result = $this.m_m365shhdb.GetServiceCommunication($Id, "RELEASEMESSAGE");
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
            "RELEASEMESSAGE"
        );

        $this.ExistsInDatabase = $true
    }
}

class ReleaseMessageHelper
{
    hidden static [M365ServiceHealthHubDB]$m_m365shhdb = [M365ServiceHealthHubDB]::new();
    
    hidden static [System.Object] GetLastSyncTimeFromDB()
    {
        return [ReleaseMessageHelper]::m_m365shhdb.GetLastSyncTime("RELEASEMESSAGE");
    }

    static [string] GetEndpoint()
    {
        return [ConfigurationManager]::ReleaseMessageEndpoint;
    }

    static [DateTime] GetLastSyncTime()
    {
        $val = [ReleaseMessageHelper]::GetLastSyncTimeFromDB();

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
        $val = [ReleaseMessageHelper]::GetLastSyncTimeFromDB();
             
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
        [ReleaseMessageHelper]::m_m365shhdb.SetLastSyncTime("RELEASEMESSAGE");
    }

    static [System.Object[]]GetReleaseMessageList()
    {
        $uri = [ReleaseMessageHelper]::GetEndpoint();

        if (![string]::IsNullOrWhiteSpace($uri))
        {
            return [ReleaseMessageHelper]::RetrieveAPIData($uri)
        } else {
            return @()
        }
    }

    hidden static [System.Object[]] RetrieveAPIData(
        [string]$Uri
    )
    {
        $result = Invoke-WebRequest -Uri $uri -UseBasicParsing
        $data = @()

        if ($result.StatusCode -ne 200)
        {
            throw "Exception caught: HTTP $($result.StatusCode): $($result.StatusDescription)"
        }
        $commList = ConvertFrom-Json $result.Content

        foreach ($comm in $commList.value)
        {
            $data += $comm
        }

        return $data
    }

    static [System.Object[]]GetReleaseMessageListFromDB(
        [System.Object[]]$CommunicationList
    )
    {
        $commList = @()

        $idList = "'" + $($($CommunicationList | Select-Object -ExpandProperty id) -join "','") + "'";

        if (![string]::IsNullOrWhiteSpace($idList))
        {
            $result = [ReleaseMessageHelper]::m_m365shhdb.GetServiceCommunicationCollection(
                $idList,
                "RELEASEMESSAGE"
            );

            foreach ($resultItem in $result.Rows)
            {              
                $item = [ReleaseMessage]::new(); 
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

    static [System.Object[]]GetReleaseMessageCollection()
    {
        $result = @()

        $comms = [ReleaseMessageHelper]::GetReleaseMessageList();     
        if ($null -ne $comms -and $comms.Count -gt 0)
        {
            $dbItems = [ReleaseMessageHelper]::GetReleaseMessageListFromDB($comms)
            foreach ($comm in $comms)
            {
                $dbComm = $dbItems | Where-Object Id -eq $comm.Id | Select-Object -First 1
                if ($null -eq $dbComm)
                {
                    $dbComm = [ReleaseMessage]::new();
                    $dbComm.ExistsInDatabase = $false;
                }
                $dbComm.GetServiceCommunicationFromMemoryObject($comm);

                $result += $dbComm
            }
        }

        return $($result | Where-Object UpdatesAvailable -eq $true)
    }
}