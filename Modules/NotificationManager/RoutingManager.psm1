using module ..\Utility.psd1
using module ..\Utility.psm1
using module ..\BaseMessage.psm1
using module ..\EntityMapping\BaseEntity.psm1
using module ..\EntityMapping\ReleaseMessageEntity.psm1
using module ..\EntityMapping\RoadmapEntity.psm1
using module ..\EntityMapping\ServiceIssueEntity.psm1
using module ..\EntityMapping\ServiceUpdateEntity.psm1
using module ..\EntityMapping\AzureServiceHealthAlertEntity.psm1
using module ..\EntityMapping\Office365EndpointsChangeEntity.psm1
using module ..\EntityMapping\AzureUpdateEntity.psm1
using module ..\EntityMapping\AzureAWSSupportTicketEntity.psm1
using module ..\EntityMapping\SystemAlertEntity.psm1
using module ..\EntityMapping\D365PowerPlatformReleaseEntity.psm1
using module ..\EntityMapping\CommonDataConnectorAlertV1Entity.psm1
using module ..\M365ServiceHealthHubDB.psm1
using module ..\ImageManager.psm1

class Route
{
    [Guid]$RouteId
    [int]$Order
    [string]$Name
    [string]$Icon
    [string]$Language
    [bool]$StopProcessingOnMatch
    [bool]$HideWorkItemLink
    [System.Object]$Conditions
    [Guid]$Connector
    [System.Object]$ConnectorConfiguration
    [Guid]$ComponentId

    Route()
    {

    }

    [System.Object]GetConnectorConfigurationValue(
        [string]$Name
    )
    {
        return $($this.ConnectorConfiguration | Where-Object name -eq $Name).value
    }

    static [string]GetIcon(
        [string]$icon
    )
    {
        if ($icon.StartsWith("imagestore://"))
        {
            $imageName = $icon.TrimStart("imagestore://");
            $image = [ImageStore]::GetImage($imageName, "notificationIcon");
            return [string]::Format("data:{0};base64,{1}", $image.Format, $image.Content);

        } else {
            return $icon;
        }
    }
}

class Routing
{
    hidden [M365ServiceHealthHubDB]$_mshh_db = [M365ServiceHealthHubDB]::new();
    [System.Collections.Generic.List[Route]]$Routing = $null;

    Routing()
    {

    }

    Routing(
        [string]$Component
    )
    {
        $this.Routing = New-Object System.Collections.Generic.List[Route];
        $routingData = $this._mshh_db.GetRoute($Component);

        foreach ($route in $routingData)
        {
            $routeObj = [Route]::new();
            $routeObj.RouteId = $route.RouteId;
            $routeObj.Order = $route.Order;
            $routeObj.Name = $route.Name;
            $routeObj.Icon = [Route]::GetIcon([string]::IsNullOrWhiteSpace($route.Icon) ? "imagestore://Office" : $route.Icon);
            $routeObj.Language = $route.Language;
            $routeObj.StopProcessingOnMatch = $route.StopProcessingOnMatch;
            $routeObj.HideWorkItemLink = $route.HideWorkItemLink;
            $routeObj.Conditions = $route.Conditions | ConvertFrom-Json | Sort-Object order;
            $routeObj.Connector = $route.Connector;
            $routeObj.ConnectorConfiguration = $route.ConnectorConfiguration | ConvertFrom-Json
            $routeObj.ComponentId = $route.ComponentId;
            $this.Routing.Add($routeObj);
        }

        $this.Routing = $this.Routing | Sort-Object Order
    }

    hidden [bool] Match(
        [Route]$Route,
        $Data
    )
    {
        if ($null -eq $Route.Conditions -or $Route.Conditions.Count -eq 0)
        {
            return $true
        }

        $match = $false;
        $previousLogicOperator = "or"

        foreach ($condition in $Route.Conditions)
        {
            if ([string]::IsNullOrWhiteSpace($condition.LogicOperator)) {
                $currentLogicOperator = "or"
            } else {
                $currentLogicOperator = $condition.LogicOperator.Trim().ToLower()
            }

            $currentMatch = $false

            switch($condition.Operator.Trim().ToLower()){
                "eq"   { $Data."$($condition.Property)" | % { $currentMatch = $currentMatch -or ($_ -eq $condition.Value)} }
                "ne"   { $Data."$($condition.Property)" | % { $currentMatch = $currentMatch -or ($_ -ne $condition.Value)} }
                "gt"   { $Data."$($condition.Property)" | % { $currentMatch = $currentMatch -or ($_ -gt $condition.Value)} }
                "ge"   { $Data."$($condition.Property)" | % { $currentMatch = $currentMatch -or ($_ -ge $condition.Value)} }
                "lt"   { $Data."$($condition.Property)" | % { $currentMatch = $currentMatch -or ($_ -lt $condition.Value)} }
                "le"   { $Data."$($condition.Property)" | % { $currentMatch = $currentMatch -or ($_ -le $condition.Value)} }
                "like" { $Data."$($condition.Property)" | % { $currentMatch = $currentMatch -or ($_ -like $condition.Value)} }
                "notlike" { $Data."$($condition.Property)" | % { $currentMatch = $currentMatch -or ($_ -notlike $condition.Value)} }
                "match" { $Data."$($condition.Property)" | % { $currentMatch = $currentMatch -or ($_ -match $condition.Value)} }
                "notmatch" { $Data."$($condition.Property)" | % { $currentMatch = $currentMatch -or ($_ -notmatch $condition.Value)} }
                "contains" { $Data."$($condition.Property)" | % { $currentMatch = $currentMatch -or ($_ -contains $condition.Value)} }
                "notcontains" { $Data."$($condition.Property)" | % { $currentMatch = $currentMatch -or ($_ -notcontains $condition.Value)} }
                "in"   { $Data."$($condition.Property)" | % { $currentMatch = $currentMatch -or ($_ -in $condition.Values)} }
                "notin"   { $Data."$($condition.Property)" | % { $currentMatch = $currentMatch -or ($_ -notin $condition.Values)} }          
            }

            switch($previousLogicOperator)
            {
                "or" { $match = $match -or $currentMatch }
                "and" { $match = $match -and $currentMatch }
            }
            $previousLogicOperator = $currentLogicOperator
        }

        return $match
    }

    hidden [System.Object] GetEntity(
        [BaseMessage]$NotificationData
    )
    {
        $entityMapper = $null;
        $dataType = $NotificationData.GetType().Name;
        switch ($dataType)
        {
            "ReleaseMessage" { $entityMapper = [ReleaseMessageEntity]::new($NotificationData); }
            "RoadmapCommunication" { $entityMapper = [RoadmapEntity]::new($NotificationData); }
            "ServiceUpdateMessage" { $entityMapper = [ServiceUpdateEntity]::new($NotificationData); }
            "ServiceHealthIssue" { $entityMapper = [ServiceIssueEntity]::new($NotificationData); }
            "AzureServiceHealthAlert" { $entityMapper = [AzureServiceHealthAlertEntity]::new($NotificationData); }
            "Office365EndpointsChange" { $entityMapper = [Office365EndpointsChangeEntity]::new($NotificationData); }
            "AzureUpdate" { $entityMapper = [AzureUpdateEntity]::new($NotificationData); }
            "AzureAWSSupportTicket" { $entityMapper = [AzureAWSSupportTicketEntity]::new($NotificationData); }
            "SystemAlert" { $entityMapper = [SystemAlertEntity]::new($NotificationData); }
            "D365PowerPlatformRelease" { $entityMapper = [D365PowerPlatformReleaseEntity]::new($NotificationData); }
            "CommonDataConnectorAlertV1" { $entityMapper = [CommonDataConnectorAlertV1Entity]::new($NotificationData); }
            default { $entityMapper = [BaseEntity]::new($NotificationData); }
        }
        return $($null -eq $entityMapper ? $null : $entityMapper.m_properties);
    }

    [System.Collections.Generic.List[Route]] GetMatches(
        [BaseMessage]$NotificationData
        )
    {
        $entityData = $this.GetEntity($NotificationData);

        $res = New-Object System.Collections.Generic.List[Route];

        $c = 0;

        foreach ($Route in $this.Routing)
        {
            $match = $this.Match($Route, $entityData)
            if ($match)
            {
                # if last route and has no conditions and no other matched rules have conditions, skip and return found routes
                # used to avoid catch-all route if other conditions are met
                if ($res.Count -gt 0 -and $($c -eq ($this.Routing.Count-1) -and $this.Routing[$c].Conditions.Count -eq 0 ))
                {
                    return $res;
                }

                $res.Add($Route); 

                $stopProcessingOnMatch = [Utility]::ParseBooleanValue($Route.StopProcessingOnMatch, $true)
                
                if ($stopProcessingOnMatch)
                {
                    return $res
                }
            }

            $c++
        }

        return $res
    }
}
