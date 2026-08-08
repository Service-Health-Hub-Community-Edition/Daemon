#region Modules
using module ..\Modules\Utility.psd1
using module ..\Modules\Utility.psm1
using module ..\Modules\ConfigurationManager.psm1
using module ..\Modules\Logging.psm1
using module ..\Modules\D365PowerPlatformRelease.psm1
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

$component = "D365PowerPlatformRelease";

$db = [M365ServiceHealthHubDB]::new($true);
$jobConfig = $db.GetComponentConfig($component);
$componentId = $($db.GetComponents().Rows | Where-Object InternalName -eq $component).ComponentId

if ($null -eq $jobConfig -or $jobConfig.enabled -eq $false) {
	[TraceLogging]::LogEvent([LoggingLevel]::Information, "D365PowerPlatformReleaseTimer", "Main", "d365ppt100", "[$component]: Job is disabled. Skipping.");
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

		$messageTypeStr = "Dynamics 365 and Power Platform Releases"
		#endregion

		[TraceLogging]::LogEvent([LoggingLevel]::Information, "D365PowerPlatformReleaseTimer", "Main", "d365ppt101", "Retrieving last sync timestamp from the database.");
		$lastSyncTime = [D365PowerPlatformReleaseHelper]::GetLastSyncTime();
		[TraceLogging]::LogEvent([LoggingLevel]::Information, "D365PowerPlatformReleaseTimer", "Main", "d365ppt102", "Last sync timestamp: $lastSyncTime.");
		[TraceLogging]::LogEvent([LoggingLevel]::Information, "D365PowerPlatformReleaseTimer", "Main", "d365ppt103", "Retrieving $messageTypeStr.");
		$serviceUpdates = [D365PowerPlatformReleaseHelper]::GetD365PowerPlatformReleaseCollection();
		[TraceLogging]::LogEvent([LoggingLevel]::Information, "D365PowerPlatformReleaseTimer", "Main", "d365ppt104", "Found $($serviceUpdates.Count) new items.");

		foreach ($serviceItem in $serviceUpdates) {		
			try {
				if (![ConfigurationManager]::GetTaskManagerConfigParameter("$([ConfigurationManager]::TaskManager).Disabled") -eq $false) {
					[TraceLogging]::LogEvent([LoggingLevel]::Information, "D365PowerPlatformReleaseTimer", "Main", "d365ppt130", "Task manager is enabled, processing the work item.");
					$taskManager.SetTask($serviceItem, $null);

					[TraceLogging]::LogEvent([LoggingLevel]::Information, "D365PowerPlatformReleaseTimer", "Main", "d365ppt131", "Work item $($serviceItem.WorkitemId) processed. Work item URL: $($serviceItem.WorkItemUrl).");
				}

				$serviceItem.Update()

				$serviceItem.Index();
			}
			catch {
				[TraceLogging]::LogEvent([LoggingLevel]::Error, "D365PowerPlatformReleaseTimer", "Main", "d365ppt181", "Couldn't process task for [$($serviceItem.Message.SnapshotId)] $($serviceItem.Message.FeatureName). Exception: $_");
			}

			try {
				[TraceLogging]::LogEvent([LoggingLevel]::Information, "D365PowerPlatformReleaseTimer", "Main", "d365ppt144", "Posting notifications for $($serviceItem.Message.SnapshotId).");
				$notificationManager.SendMessage($serviceItem);
			}
			catch
			{
				[TraceLogging]::LogEvent([LoggingLevel]::Error, "D365PowerPlatformReleaseTimer", "Main", "d365ppt182", "Couldn't post notificaction for [$($serviceItem.Message.SnapshotId)] $($serviceItem.Message.FeatureName). Exception: $_");
			}
		}

		[TraceLogging]::LogEvent([LoggingLevel]::Information, "D365PowerPlatformReleaseTimer", "Main", "d365ppt198", "Registering a synchronization heartbeat.");
		[D365PowerPlatformReleaseHelper]::SetLastSyncTimestamp();
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

[TraceLogging]::LogEvent([LoggingLevel]::Information, "D365PowerPlatformReleaseTimer", "Main", "d365ppt199", "All operations completed successfully.");