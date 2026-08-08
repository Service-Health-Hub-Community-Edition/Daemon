using module ..\ImageManager.psm1
using module ..\Logging.psm1
using module ..\Utility.psd1
using module ..\Utility.psm1
using module ..\ConfigurationManager.psm1
using module ..\M365ServiceHealthHubDB.psm1

$version = "2.0.2208.0";
$global:M365HHDBSchemaCheckCompleted = $true; # disable schema upgrade during post-upgrade procedure

function Get-FileNameFromUrl(
    [string]$url)
{
    $uri = [uri]::new($url);
    if ($uri.Segments.Length -gt 0)
    {
        return $uri.segments[$uri.segments.length-1];
    } else {
        return [string]::Empty;
    }
}

function Get-ImageStoreMap(
    [string]$Type
)
{
    $imageStoreUri = "https://servicehealthhub.blob.core.windows.net/imagestore/store.json"
    [System.Collections.Generic.Dictionary[[string], [string]]]$map = New-Object "System.Collections.Generic.Dictionary[[string], [string]]";
    $apiData = Invoke-RestMethod -Uri $imageStoreUri -Method Get
    $apiData = $apiData | Sort-Object published;

    foreach ($version in $apiData)
    {
        $imageCollection = $null;
        if ([string]::IsNullOrWhiteSpace($Type))
        {
            $imageCollection = $version.add
        } else {
            $imageCollection = $version.add | Where-Object Type -eq $Type
        }

        foreach ($image in $imageCollection)
        {
            $fileName = Get-FileNameFromUrl($image.Url).ToLower();
            $newUrl = "imagestore://$($image.Name)";

            if ($map.ContainsKey($fileName))
            {
                $map[$fileName]=$newUrl;
            } else {
                $map.Add($fileName, $newUrl);
            }
        }
    }

    return $map;
}

function Move-RoutingRules()
{
    [TraceLogging]::LogEvent(
        [LoggingLevel]::Information,
        "Upgrade",
        $version, "upg2208-0-0100",
        [string]::Format(
            "Move-RoutingRules: Entering Move-RoutingRules function.",
            $version));

    $componentInternalNames = @('ServiceUpdateMessage', 'ServiceHealthIssue', 'RoadmapCommunication', 'ReleaseMessage', 'AzureServiceHealthAlert')

    [TraceLogging]::LogEvent(
        [LoggingLevel]::Information,
        "Upgrade",
        $version, "upg2208-0-0101",
        [string]::Format(
            "Move-RoutingRules: Retrieving image store map.",
            $version));

    $imageStoreMap = Get-ImageStoreMap -Type "notificationIcon";

    [TraceLogging]::LogEvent(
        [LoggingLevel]::Information,
        "Upgrade",
        $version, "upg2208-0-0102",
        [string]::Format(
            "Move-RoutingRules: Retrieving Service Health Hub components.",
            $version));
            
    $m_m365shhdb = [M365ServiceHealthHubDB]::new();
    $notificationManager = $env:NotificationManager
    $connectorId = [Guid]::Empty;
    $components = $m_m365shhdb.GetComponents()

    if ($notificationManager -eq 'Teams')
    {
        $connectorId = [Guid]'e3990fbe-4fb9-4967-884c-2dc76ac819f4';

        [TraceLogging]::LogEvent(
            [LoggingLevel]::Information,
            "Upgrade",
            $version, "upg2208-0-0103",
            [string]::Format(
                "Move-RoutingRules: Legacy notification manager: Teams. Connector id: $($connectorId.ToString())",
                $version));
    } 
    elseif ($notificationManager -eq 'LogicAppsNotifications')
    {
        $logicAppEndpoint = [ConfigurationManager]::GetNotificationManagerConfigParameter('LogicAppsNotifications.Endpoint');
        if (![string]::IsNullOrWhiteSpace($logicAppEndpoint))
        {
            $logicAppEndpoint = $logicAppEndpoint.Trim();
            $connectors = $m_m365shhdb.GetNotificationManagerConnectors();
            foreach ($connector in $connectors.Rows)
            {
                $connectorConfig = $connector.Configuration | ConvertFrom-Json
                $endpointEntry = $connectorConfig | Where-Object name -eq "Endpoint" | Select-Object -First 1
                if ($null -ne $endpointEntry -and $endpointEntry.value.Trim() -eq $logicAppEndpoint)
                {
                    $connectorId = $connector.ConnectorId;
                    break;
                }
            }
        }

        # if conenctor is not found, create a logic app connector.

        if ($connectorId -eq [Guid]::Empty)
        {
            [TraceLogging]::LogEvent(
                [LoggingLevel]::Information,
                "Upgrade",
                $version, "upg2208-0-0104",
                [string]::Format(
                    "Move-RoutingRules: Legacy notification manager: LogicAppsNotifications. Connector not found. Creating.)",
                    $version));

            $id = [Guid]::NewGuid();
            $connector = New-Object -TypeName PSObject;
            Add-Member -InputObject $connector -NotePropertyName "ConnectorId" -NotePropertyValue $id;
            Add-Member -InputObject $connector -NotePropertyName "Name" -NotePropertyValue "Microsoft Teams via Logic App"
            Add-Member -InputObject $connector -NotePropertyName "Type" -NotePropertyValue $([Guid]"e865a99d-44b2-4f3d-9c94-523c30fce3b0");

            $connectorConfig = New-Object "System.Collections.Generic.List[object]"
            $connectorConfigItem = New-Object -TypeName PSObject;
            Add-Member -InputObject $connectorConfigItem -NotePropertyName "name" -NotePropertyValue "Endpoint";
            Add-Member -InputObject $connectorConfigItem -NotePropertyName "value" -NotePropertyValue [ConfigurationManager]::GetNotificationManagerConfigParameter('LogicAppsNotifications.Endpoint');
            $connectorConfig.Add($connectorConfigItem);

            Add-Member -InputObject $connector -NotePropertyName "Configuration" -NotePropertyValue $connectorConfig
            
            $m_m365shhdb.AddConnector($connector);
            $connectorId = $id;
        }

        [TraceLogging]::LogEvent(
            [LoggingLevel]::Information,
            "Upgrade",
            $version, "upg2208-0-0108",
            [string]::Format(
                "Move-RoutingRules: Legacy notification manager: LogicAppsNotifications. Connector id: $($connectorId.ToString())",
                $version));
    }

    if ($connectorId -ne [Guid]::Empty)
    {
        foreach ($component in $componentInternalNames)
        {
            $currentComponent = $components.Rows | Where-Object InternalName -eq $component
            if (![string]::IsNullOrWhiteSpace($currentComponent))
            {
                $routing = $m_m365shhdb.GetSyncConfigEntry($component, 'routing') | ConvertFrom-Json
                foreach ($route in $routing.Routing)
                {
                    $newRoute = New-Object -TypeName PSObject
                    Add-Member -InputObject $newRoute -NotePropertyName Order -NotePropertyValue $route.ID
                    Add-Member -InputObject $newRoute -NotePropertyName Name -NotePropertyValue $route.Name

                    $icon = $route.Icon;
                    if ($null -ne $icon -and !$icon.StartsWith("imagestore://"))
                    {
                        $fileName = Get-FileNameFromUrl($icon).ToLower();
                        $newIcon = [string]::Empty;
                        if (![string]::IsNullOrWhiteSpace($fileName))
                        {
                            if ($imageStoreMap.ContainsKey($fileName))
                            {
                                $newIcon = $imageStoreMap[$fileName];
                            }
                        }

                        if (![string]::IsNullOrWhiteSpace($newIcon))
                        {
                            $icon = $newIcon;
                        }
                    }

                    Add-Member -InputObject $newRoute -NotePropertyName Icon -NotePropertyValue $icon
                    Add-Member -InputObject $newRoute -NotePropertyName Connector -NotePropertyValue $connectorId
                    Add-Member -InputObject $newRoute -NotePropertyName Component -NotePropertyValue $currentComponent.ComponentId
                    Add-Member -InputObject $newRoute -NotePropertyName Language -NotePropertyValue $(![string]::IsNullOrWhiteSpace($route.Language) ? $route.Language : '')
                    Add-Member -InputObject $newRoute -NotePropertyName StopProcessingOnMatch -NotePropertyValue $(![string]::IsNullOrWhiteSpace($route.StopProcessingOnMatch) ? [Utility]::ParseBooleanValue($route.StopProcessingOnMatch, $true) : $true)
                    Add-Member -InputObject $newRoute -NotePropertyName HideWorkItemLink -NotePropertyValue $(![string]::IsNullOrWhiteSpace($route.HideWorkItemLink) ? [Utility]::ParseBooleanValue($route.HideWorkItemLink, $false) : $false)

                    $connectorConfig = @()
                    
                    if ($connectorId -eq [Guid]'e3990fbe-4fb9-4967-884c-2dc76ac819f4')
                    {
                        $configElement = New-Object -TypeName PSObject
                        Add-Member -InputObject $configElement -NotePropertyName 'name' -NotePropertyValue 'TeamsChannelUri';
                        Add-Member -InputObject $configElement -NotePropertyName 'value' -NotePropertyValue $route.TeamsChannelUri;
                        $connectorConfig += $configElement
                    } else {
                        $configElement = New-Object -TypeName PSObject
                        Add-Member -InputObject $configElement -NotePropertyName 'name' -NotePropertyValue 'teamId';
                        Add-Member -InputObject $configElement -NotePropertyName 'value' -NotePropertyValue $route.TeamId;
                        $connectorConfig += $configElement

                        $configElement = New-Object -TypeName PSObject
                        Add-Member -InputObject $configElement -NotePropertyName 'name' -NotePropertyValue 'channelId';
                        Add-Member -InputObject $configElement -NotePropertyName 'value' -NotePropertyValue $route.ChannelId;
                        $connectorConfig += $configElement
                    }
                    
                    Add-Member -InputObject $newRoute -NotePropertyName ConnectorConfiguration -NotePropertyValue $connectorConfig

                    $conditions = @();
                    $conditionOrder = 0;

                    foreach ($condition in $route.Conditions)
                    {
                        $newCondition = New-Object -TypeName PSObject
                        $valuesCollection = @()
                        Add-Member -InputObject $newCondition -NotePropertyName "key" -NotePropertyValue $([Guid]::NewGuid())
                        Add-Member -InputObject $newCondition -NotePropertyName "property" -NotePropertyValue $condition.Property
                        Add-Member -InputObject $newCondition -NotePropertyName "operator" -NotePropertyValue $condition.Operator
                        Add-Member -InputObject $newCondition -NotePropertyName "value" -NotePropertyValue $(![string]::IsNullOrWhiteSpace($condition.Value) ? $condition.Value : "")
                        foreach ($value in $condition.Values)
                        {
                            $valuesCollection += $value
                        }
                        Add-Member -InputObject $newCondition -NotePropertyName "values" -NotePropertyValue $valuesCollection
                        Add-Member -InputObject $newCondition -NotePropertyName "logicOperator" -NotePropertyValue $(![string]::IsNullOrWhiteSpace($condition.LogicOperator) ? $condition.LogicOperator : "")
                        Add-Member -InputObject $newCondition -NotePropertyName "order" -NotePropertyValue $conditionOrder
                        $conditions += $newCondition
                        $conditionOrder++;
                    }

                    Add-Member -InputObject $newRoute -NotePropertyName "conditions" -NotePropertyValue $conditions
                    [TraceLogging]::LogEvent(
                        [LoggingLevel]::Information,
                        "Upgrade",
                        $version, "upg2208-0-0111",
                        [string]::Format(
                            "Move-RoutingRules: Added route $($route.ID) for component $($currentComponent.ComponentId)",
                            $version));
                    $m_m365shhdb.AddRoute($newRoute);
                }
            }
        }
        } else {
            [TraceLogging]::LogEvent(
                [LoggingLevel]::Warning,
                "Upgrade",
                $version, "upg2208-0-01a0",
                [string]::Format(
                    "Move-RoutingRules: Couldn't find relevant notification connector. Create a connector within Microsoft Service Health Hub Admin Center and try again.",
                    $version));
    }

    [TraceLogging]::LogEvent(
        [LoggingLevel]::Information,
        "Upgrade",
        $version, "upg2208-0-01ff",
        [string]::Format(
            "Move-RoutingRules: Exiting Move-RoutingRules function.",
            $version));
}

[TraceLogging]::LogEvent(
    [LoggingLevel]::Information,
    "Upgrade",
    $version, "upg2208-0-0000",
    [string]::Format(
        "{0}: Entering post-upgrade procedure.",
        $version));

[TraceLogging]::LogEvent(
    [LoggingLevel]::Information,
    "Upgrade",
    $version, "upg2208-0-0001",
    [string]::Format(
        "{0}: Importing images to the image store.",
        $version));

[ImageStore]::ProcessImageStoreUpdates();

[TraceLogging]::LogEvent(
    [LoggingLevel]::Information,
    "Upgrade",
    $version, "upg2208-0-0010",
    [string]::Format(
        "{0}: Migrating routing rules.",
        $version));

Move-RoutingRules

[TraceLogging]::LogEvent(
    [LoggingLevel]::Information,
    "Upgrade",
    $version, "upg2208-0-00ff",
    [string]::Format(
        "{0}: Exiting post-upgrade procedure.",
        $version));