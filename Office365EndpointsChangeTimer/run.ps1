#region Modules
using module ..\Modules\Utility.psd1
using module ..\Modules\Utility.psm1
using module ..\Modules\ConfigurationManager.psm1
using module ..\Modules\RulesEngine.psm1
using module ..\Modules\Logging.psm1
using module ..\Modules\DataSource\Office365EndpointSets.psm1
using module ..\Modules\TaskManager\TaskManager.psm1
using module ..\Modules\NotificationManager\NotificationManager.psm1
using module ..\Modules\M365ServiceHealthHubDB.psm1
#endregion

# Input bindings are passed in via param block.
param($Timer)

#region Init
[TraceLogging]::InitializeCorrelationID();
$global:systemAlert = [NotificationManager]::new("SystemAlert");
#endregion

$component = "Office365EndpointsChange";


$db = [M365ServiceHealthHubDB]::new($true);
$jobConfig = $db.GetComponentConfig($component);
$componentId = $($db.GetComponents().Rows | Where-Object InternalName -eq $component).ComponentId

if ($null -eq $jobConfig -or $jobConfig.enabled -eq $false) {
	[TraceLogging]::LogEvent([LoggingLevel]::Information, "Office365EndpointsChangeTimer", "Main", "sit100", "[$component]: Job is disabled. Skipping.");
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

	try {
		$taskManager = [TaskManager]::CreateInstance(
			[ConfigurationManager]::TaskManager,
			$component
		);

		$notificationManager = [NotificationManager]::new($component);
		#endregion

		$endpointSetChanges = [Office365EndpointSetChanges]::GetChanges()
		[TraceLogging]::LogEvent([LoggingLevel]::Information, "Office365EndpointsChangeTimer", "Main", "oec104", "$($endpointSetChanges.Changes.Count) items retrieved.");
		$latestVersion = "0000000000"
		$success = $true

		foreach ($change in $endpointSetChanges.Changes) {
			$serviceComm = [Office365EndpointsChange]::new();
			$serviceComm.Set($change);

			try {
				if ($serviceComm.UpdatesAvailable) {
					if (![ConfigurationManager]::GetTaskManagerConfigParameter("$([ConfigurationManager]::TaskManager).Disabled") -eq $false) {
						[TraceLogging]::LogEvent([LoggingLevel]::Information, "Office365EndpointsChangeTimer", "Main", "oec130", "Processing work item for change $($change.Id).");
						$taskManager.SetTask($serviceComm, $null);
						[TraceLogging]::LogEvent([LoggingLevel]::Information, "Office365EndpointsChangeTimer", "Main", "oec131", "Work item $($serviceComm.WorkitemId) processed. Work item URL: $($serviceComm.WorkItemUrl).");
					}

					$serviceComm.Update();

				}
				else {
					[TraceLogging]::LogEvent([LoggingLevel]::Information, "Office365EndpointsChangeTimer", "Main", "oec151", "No updates available for change $($change.Id). Skipping.");
				}
			
			}
			catch {
				[TraceLogging]::LogEvent([LoggingLevel]::Error, "Office365EndpointsChangeTimer", "Main", "oec181", "Couldn't process change $($chage.Id). Exception: $_");
				$success = $false
			}

			try {
				[TraceLogging]::LogEvent([LoggingLevel]::Information, "Office365EndpointsChangeTimer", "Main", "oec144", "Posting notifications for change $($change.Id).");
				$notificationManager.SendMessage($serviceComm);
			}
			catch
			{
				[TraceLogging]::LogEvent([LoggingLevel]::Error, "Office365EndpointsChangeTimer", "Main", "oec182", "Couldn't post notificaction for [$($serviceItem.Message.Id)] $($serviceItem.Message.Title). Exception: $_");
			}

			if ($change.Version -gt $latestVersion) {
				$latestVersion = $change.Version
			}
		}

		if ($success) {
			if ($latestVersion -ne "0000000000") {
				[TraceLogging]::LogEvent([LoggingLevel]::Information, "Office365EndpointsChangeTimer", "Main", "oec198", "Updating last synchronized version to $latestVersion.");
				[Office365EndpointSetChanges]::SetLastSyncedVersion($latestVersion);
			}
		}
		else {
			[TraceLogging]::LogEvent([LoggingLevel]::Error, "Office365EndpointsChangeTimer", "Main", "oec198", "Issues detected during the synchronization. Please review the logs and fix outstanding issues. The synchronization will be retried on the next schedule.");
		}
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
			$_,
			$null
		);
	}
 finally {
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
}

[TraceLogging]::LogEvent([LoggingLevel]::Information, "Office365EndpointsChangeTimer", "Main", "oec1ff", "All operations completed successfully.");