#region Modules
using module ..\Modules\Utility.psd1
using module ..\Modules\Utility.psm1
using module ..\Modules\ConfigurationManager.psm1
using module ..\Modules\RulesEngine.psm1
using module ..\Modules\Logging.psm1
using module ..\Modules\AzureAWSSupportTicket.psm1
using module ..\Modules\TaskManager\TaskManager.psm1
using module ..\Modules\NotificationManager\NotificationManager.psm1
using module ..\Modules\ServiceAlert.psm1
using module ..\Modules\M365ServiceHealthHubDB.psm1
#endregion

# Input bindings are passed in via param block.
param($mySbMsg, $TriggerMetadata)

#region Init
[TraceLogging]::InitializeCorrelationID();
$global:systemAlert = [NotificationManager]::new("SystemAlert");
#endregion

[TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureAWSSupportTicketWebhook", "Main", "aat103", "Procesing Azure / AWS Support Ticket.");

$component = "AzureAWSSupportTicket";

$db = [M365ServiceHealthHubDB]::new($true);
$jobConfig = $db.GetComponentConfig($component);
$componentId = $($db.GetComponents().Rows | Where-Object InternalName -eq $component).ComponentId
$success = $true;

if ($null -eq $jobConfig -or $jobConfig.enabled -eq $false) {
    [TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureAWSSupportTicketWebhook", "Main", "aat100", "[$component]: Job is disabled. Skipping.");
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

    $payload = ConvertTo-Json $mySbMsg -Depth 15
    $serviceItem = [AzureAWSSupportTicket]::new();
    [TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureAWSSupportTicketWebhook", "Main", "aat129a", "Payload: $payload");
    $serviceItem.SetAzureAWSSupportTicket($payload);

    try {
        $taskManager = [TaskManager]::CreateInstance(
            [ConfigurationManager]::TaskManager,
            $component
        );

        $notificationManager = [NotificationManager]::new($component);

        try {
            if (![ConfigurationManager]::GetTaskManagerConfigParameter("$([ConfigurationManager]::TaskManager).Disabled") -eq $false) {
                [TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureAWSSupportTicketWebhook", "Main", "aat130", "Task manager is enabled, processing the work item.");
                $taskManager.SetTask($serviceItem, $null);
                [TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureAWSSupportTicketWebhook", "Main", "aat131", "Work item $($serviceItem.WorkitemId) processed. Work item URL: $($serviceItem.WorkItemUrl).");
            }
        }
        catch {
            $success = $false
            [TraceLogging]::LogEvent([LoggingLevel]::Error, "AzureAWSSupportTicketWebhook", "Main", "aat181", "Couldn't task for [$($serviceItem.Message.id)] $($serviceItem.Message.title). Exception: $_");
        }

        try {
            [TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureAWSSupportTicketWebhook", "Main", "aat144", "Posting notifications for $($serviceItem.Message.id).");
            $notificationManager.SendMessage($serviceItem);
        }
        catch
        {
            [TraceLogging]::LogEvent([LoggingLevel]::Error, "AzureAWSSupportTicketWebhook", "Main", "aat182", "Couldn't post notificaction for [$($serviceItem.Message.id)] $($serviceItem.Message.title). Exception: $_");
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
        if (!$success)
        {
            throw "An error occured during message processing."
        }
        
        $serviceItem.Update();
    }
}

[TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureAWSSupportTicketWebhook", "Main", "aat199", "All operations completed.");