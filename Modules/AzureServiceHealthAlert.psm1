using module .\BaseMessage.psm1
using module .\M365ServiceHealthHubDB.psm1
using module .\AuthManager.psm1

class AzureServiceHealthAlert: BaseMessage
{
    hidden [M365ServiceHealthHubDB]$m_m365shhdb = [M365ServiceHealthHubDB]::new();

    AzureServiceHealthAlert()
    {

    }

    AzureServiceHealthAlert(
        [string]$Id
    )
    {
        $this.GetServiceCommunicationFromDatabase($Id)
    }

    [void]SetAzureServiceHealthAlert(
        [string]$JsonData
    )
    {
        $messageObj = ConvertFrom-Json $JsonData

        $monitoringService = ${messageObj}.data.essentials.monitoringService;
        if (![string]::IsNullOrWhiteSpace($monitoringService) -and $monitoringService.Trim().ToUpper() -eq "SERVICEHEALTH") {
            
            if ($null -ne $messageObj.data.alertContext.properties.trackingId) {
                $this.GetServiceCommunicationFromDatabase($messageObj.data.alertContext.properties.trackingId);
            }

            $this.MessageJson = ConvertTo-Json $messageObj -Depth 10
        } else {
            throw "Message is not provided in supported format."
        }

        $this.DeserializeMessage();
        
        if ($null -ne $this.Message.data.essentials.firedDateTime){
            $apiLastUpdatedDateTime = [DateTime]::new(
                $this.Message.data.essentials.firedDateTime.Year,
                $this.Message.data.essentials.firedDateTime.Month,
                $this.Message.data.essentials.firedDateTime.Day,
                $this.Message.data.essentials.firedDateTime.Hour,
                $this.Message.data.essentials.firedDateTime.Minute,
                $this.Message.data.essentials.firedDateTime.Second
            ); #make sure we ignore miliseconds
            $this.UpdatesAvailable = $apiLastUpdatedDateTime -gt $this.LastUpdatedTime;
            $this.LastUpdatedTime = $apiLastUpdatedDateTime;
        }
    }

    hidden [void]DeserializeMessage()
    {
        $messageObj = ConvertFrom-Json $this.MessageJson
        if ($null -ne $messageObj.data.alertContext.properties.trackingId) {
            $this.Message = $messageObj
            $this.Id = $messageObj.data.alertContext.properties.trackingId
        }
        else {
            throw "Message is not provided in supported format."
        }
    }

    [void]GetServiceCommunicationFromDatabase(
        [string]$Id
    )
    {
        $result = $this.m_m365shhdb.GetServiceCommunication($Id, "AZURESERVICEHEALTHALERT");
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
            "AZURESERVICEHEALTHALERT"
        );

        $this.ExistsInDatabase = $true
    }
}

class AzureServiceHealthAlertHelper
{
    hidden static [M365ServiceHealthHubDB]$m_db = [M365ServiceHealthHubDB]::new();

    static [System.Object[]]GetServiceHealthAlertsFromDB()
    {
        $commList = @()

        $result = [AzureServiceHealthAlertHelper]::m_db.GetServiceCommunicationCollection("AZURESERVICEHEALTHALERT");
        
        foreach ($resultItem in $result.Rows)
        {              
            $item = [AzureServiceHealthAlert]::new(); 
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