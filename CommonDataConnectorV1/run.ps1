#region Modules
using module ..\Modules\Utility.psd1
using module ..\Modules\Utility.psm1
using module ..\Modules\ConfigurationManager.psm1
using module ..\Modules\RulesEngine.psm1
using module ..\Modules\Logging.psm1
using module ..\Modules\CommonDataConnectorAlertV1.psm1
using module ..\Modules\TaskManager\TaskManager.psm1
using module ..\Modules\NotificationManager\NotificationManager.psm1
using module ..\Modules\M365ServiceHealthHubDB.psm1
#endregion

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

#region Init
[TraceLogging]::InitializeCorrelationID();
$global:systemAlert = [NotificationManager]::new("SystemAlert");
#endregion

[TraceLogging]::LogEvent([LoggingLevel]::Information, "Config", "Main", "cdcv1103", "Procesing Common Data Connector Alert.");

$component = "CommonDataConnectorAlertV1";

$db = [M365ServiceHealthHubDB]::new($true);
$jobConfig = $db.GetComponentConfig($component);
$componentId = $($db.GetComponents().Rows | Where-Object InternalName -eq $component).ComponentId

if ($null -eq $jobConfig -or $jobConfig.enabled -eq $false) {
    [TraceLogging]::LogEvent([LoggingLevel]::Information, "CommonDataConnectorV1", "Main", "cdcv1100", "[$component]: Job is disabled. Skipping.");
}
else {
    $db.AddActivityLogRecord(
        [Guid]::Empty,
        [TraceLogging]::CorrelationID,
        '',
        'app-' + [ConfigurationManager]::ClientId + '@' + [ConfigurationManager]::TenantDomain,
        'JobStarted',
        'item://' + $component,
        'Job',
        [Guid]::Empty,
        "",
        $component,
        $componentId,
        $null,
        $null
    );

    $payload = ConvertTo-Json $Request.Body -Depth 10
    $serviceItem = [CommonDataConnectorAlertV1]::new();
    $serviceItem.SetCommonDataConnectorAlertV1($payload);

    try {
        $taskManager = [TaskManager]::CreateInstance(
            [ConfigurationManager]::TaskManager,
            $component
        );

        $notificationManager = [NotificationManager]::new($component);

        try {
            if (![ConfigurationManager]::GetTaskManagerConfigParameter("$([ConfigurationManager]::TaskManager).Disabled") -eq $false) {
                [TraceLogging]::LogEvent([LoggingLevel]::Information, "CommonDataConnectorV1", "Main", "cdcv1130", "Task manager is enabled, processing the work item.");
                $taskManager.SetTask($serviceItem, $null);
                [TraceLogging]::LogEvent([LoggingLevel]::Information, "CommonDataConnectorV1", "Main", "cdcv1131", "Work item $($serviceItem.WorkitemId) processed. Work item URL: $($serviceItem.WorkItemUrl).");
            }
        }
        catch {
            [TraceLogging]::LogEvent([LoggingLevel]::Error, "CommonDataConnectorV1", "Main", "cdcv1181", "Couldn't task for [$($serviceItem.Message.data.alertContext.properties.trackingId)] $($serviceItem.Message.data.alertContext.properties.title). Exception: $_");
        }

        try {
            [TraceLogging]::LogEvent([LoggingLevel]::Information, "CommonDataConnectorV1", "Main", "cdcv1144", "Posting notifications for $($serviceItem.Message.data.alertContext.properties.trackingId).");
            $notificationManager.SendMessage($serviceItem);
        }
        catch
        {
            [TraceLogging]::LogEvent([LoggingLevel]::Error, "CommonDataConnectorV1", "Main", "cdcv1182", "Couldn't post notificaction for [$($serviceItem.Message.data.alertContext.properties.trackingId)] $($serviceItem.Message.data.alertContext.properties.title). Exception: $_");
        }	

        $db.AddActivityLogRecord(
            [Guid]::Empty,
            [TraceLogging]::CorrelationID,
            '',
            'app-' + [ConfigurationManager]::ClientId + '@' + [ConfigurationManager]::TenantDomain,
            'JobCompleted',
            'item://' + $component,
            'Job',
            [Guid]::Empty,
            "",
            $component,
            $componentId,
            $null,
            $null
        );
    }
    catch {
        $db.AddActivityLogRecord(
            [Guid]::Empty,
            [TraceLogging]::CorrelationID,
            '',
            'app-' + [ConfigurationManager]::ClientId + '@' + [ConfigurationManager]::TenantDomain,
            'JobFailed',
            'item://' + $component,
            'Job',
            [Guid]::Empty,
            "",
            $component,
            $componentId,
            $($null -ne $_.Exception ? $_.Exception.ToString() : $_.ToString()),
            $null
        );
    }
    finally {
        $serviceItem.Update();
    }
}

[TraceLogging]::LogEvent([LoggingLevel]::Information, "Config", "Main", "cdcv1199", "All operations completed.");

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [System.Net.HttpStatusCode]::OK
        Body       = ""
    })