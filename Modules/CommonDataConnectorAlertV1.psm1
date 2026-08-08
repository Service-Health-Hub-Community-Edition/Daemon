using module .\BaseMessage.psm1
using module .\M365ServiceHealthHubDB.psm1
using module .\AuthManager.psm1

<#
    CommonDataConnectorAlertV1 properties:
    id: Guid
    title: string
    description: string
    status: string
    type: string
    source: string
    resource: string
    tags: string[]
    startTime: DateTime
    endTime: DateTime
    lastUpdate: DateTime
    additionalData: object
#>

class CommonDataConnectorAlertV1: BaseMessage
{
    hidden [M365ServiceHealthHubDB]$m_m365shhdb = [M365ServiceHealthHubDB]::new();

    CommonDataConnectorAlertV1()
    {

    }

    CommonDataConnectorAlertV1(
        [string]$Id
    )
    {
        $this.GetServiceCommunicationFromDatabase($Id)
    }

    [void]SetCommonDataConnectorAlertV1(
        [string]$JsonData
    )
    {
        $messageObj = ConvertFrom-Json $JsonData

        if ($null -ne $messageObj.id) {
            $this.GetServiceCommunicationFromDatabase($messageObj.id);
        }

        $this.MessageJson = ConvertTo-Json $messageObj -Depth 10

        $this.DeserializeMessage();
        
        if ($null -ne $this.Message.lastUpdate){
            $apiLastUpdatedDateTime = [DateTime]::new(
                $this.Message.lastUpdate.Year,
                $this.Message.lastUpdate.Month,
                $this.Message.lastUpdate.Day,
                $this.Message.lastUpdate.Hour,
                $this.Message.lastUpdate.Minute,
                $this.Message.lastUpdate.Second
            ); #make sure we ignore miliseconds
            $this.UpdatesAvailable = $apiLastUpdatedDateTime -gt $this.LastUpdatedTime;
            $this.LastUpdatedTime = $apiLastUpdatedDateTime;
        }
    }

    hidden [void]DeserializeMessage()
    {
        $messageObj = ConvertFrom-Json $this.MessageJson
        if ($null -ne $messageObj.id) {
            $this.Message = $messageObj
            $this.Id = $messageObj.id
        }
        else {
            throw "Message is not provided in supported format."
        }
    }

    [void]GetServiceCommunicationFromDatabase(
        [string]$Id
    )
    {
        $result = $this.m_m365shhdb.GetServiceCommunication($Id, "CommonDataConnectorAlertV1");
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
            "CommonDataConnectorAlertV1"
        );

        $this.ExistsInDatabase = $true
    }
}

class CommonDataConnectorAlertV1Helper
{
    hidden static [M365ServiceHealthHubDB]$m_db = [M365ServiceHealthHubDB]::new();

    static [System.Object[]]GetServiceHealthAlertsFromDB()
    {
        $commList = @()

        $result = [CommonDataConnectorAlertV1Helper]::m_db.GetServiceCommunicationCollection("CommonDataConnectorAlertV1");
        
        foreach ($resultItem in $result.Rows)
        {              
            $item = [CommonDataConnectorAlertV1]::new(); 
            $item.ExistsInDatabase = $true;
            $item.Id = $resultItem.TicketId;
            $item.LastUpdatedTime = $resultItem.LastUpdatedTime;
            $item.MessageJson = $resultItem.Data;
            $item.WorkItemId = $resultItem.WorkItemID;
            $item.WorkItemUrl = $resultItem.WorkItemURL;
            $item.DeserializeMessage();

            $commList += $item
        }

        return $commList
    }
}