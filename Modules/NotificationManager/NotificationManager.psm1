using module .\NotificationManagerBase.psm1
using module .\NotificationConnector.psm1
using module .\RoutingManager.psm1
using module ..\M365ServiceHealthHubDB.psm1
using module ..\BaseMessage.psm1

class NotificationManager
{
    hidden [M365ServiceHealthHubDB]$_mshh_db = [M365ServiceHealthHubDB]::new();
    [System.Collections.Generic.List[NotificationConnector]]$Connectors = $null;
    [Routing]$Routing = $null;

    NotificationManager(
        [string]$Component
    )
    {
        $this.Connectors = New-Object System.Collections.Generic.List[NotificationConnector];
        [System.Object[]]$ConnectorList = $this._mshh_db.GetNotificationManagerConnectors();
        foreach ($connector in $ConnectorList.Rows)
        {
            $connectorObj = [NotificationConnector]::new($connector, $Component);
            $this.Connectors.Add($connectorObj);
        }
        
        $this.Routing = [Routing]::new($Component);
    }

    [NotificationConnector]GetConnector(
        [Guid]$Id
    )
    {
        return $($this.Connectors | Where-Object ConnectorId -eq $Id);
    }

    [void]SendMessage(
		[BaseMessage]$ServiceCommunication
	)
    {
        $routingMatches = $this.Routing.GetMatches($ServiceCommunication);

        foreach ($route in $routingMatches)
        {
            $connector = $this.GetConnector($route.Connector);
            $connector.Instance.SendMessage($ServiceCommunication, $route);
        }
    }
}