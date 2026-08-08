#region Modules
using module ..\Modules\Utility.psd1
using module ..\Modules\Utility.psm1
using module ..\Modules\ConfigurationManager.psm1
using module ..\Modules\RulesEngine.psm1
using module ..\Modules\Logging.psm1
using module ..\Modules\ReleaseMessaging.psm1
using module ..\Modules\TaskManager\TaskManager.psm1
using module ..\Modules\NotificationManager\NotificationManager.psm1
using module ..\Modules\M365ServiceHealthHubDB.psm1
using module ..\Modules\ImageManager.psm1
#endregion

# Input bindings are passed in via param block.
param($Timer)

#region Init
[TraceLogging]::InitializeCorrelationID();
$global:systemAlert = [NotificationManager]::new("SystemAlert");
#endregion

$component = "ReleaseMessage";

$db = [M365ServiceHealthHubDB]::new($true);
$jobConfig = $db.GetComponentConfig($component);
$componentId = $($db.GetComponents().Rows | Where-Object InternalName -eq $component).ComponentId

if ($null -eq $jobConfig -or $jobConfig.enabled -eq $false) {
	[TraceLogging]::LogEvent([LoggingLevel]::Information, "ReleaseMessageTimer", "Main", "rmt100", "[$component]: Job is disabled. Skipping.");
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

		$messageTypeStr = "M365 Service Health Hub Release"
		#endregion

		[TraceLogging]::LogEvent([LoggingLevel]::Information, "ReleaseMessageTimer", "Main", "rmt101", "Retrieving last sync timestamp from the database.");
		$lastSyncTime = [ReleaseMessageHelper]::GetLastSyncTime();
		[TraceLogging]::LogEvent([LoggingLevel]::Information, "ReleaseMessageTimer", "Main", "rmt102", "Last sync timestamp: $lastSyncTime.");
		[TraceLogging]::LogEvent([LoggingLevel]::Information, "ReleaseMessageTimer", "Main", "rmt103", "Retrieving $messageTypeStr.");
		$serviceUpdates = [ReleaseMessageHelper]::GetReleaseMessageCollection();
		[TraceLogging]::LogEvent([LoggingLevel]::Information, "ReleaseMessageTimer", "Main", "rmt104", "Found $($serviceUpdates.Count) new items.");

		foreach ($serviceItem in $serviceUpdates) {		
			try {
				if (![ConfigurationManager]::GetTaskManagerConfigParameter("$([ConfigurationManager]::TaskManager).Disabled") -eq $false) {
					[TraceLogging]::LogEvent([LoggingLevel]::Information, "ReleaseMessageTimer", "Main", "rmt130", "Task manager is enabled, processing the work item.");
					$taskManager.SetTask($serviceItem, $null);

					[TraceLogging]::LogEvent([LoggingLevel]::Information, "ReleaseMessageTimer", "Main", "rmt131", "Work item $($serviceItem.WorkitemId) processed. Work item URL: $($serviceItem.WorkItemUrl).");
				}

				$serviceItem.Update()
			}
			catch {
				[TraceLogging]::LogEvent([LoggingLevel]::Error, "ReleaseMessageTimer", "Main", "rmt181", "Couldn't process task for [$($serviceItem.Message.Id)] $($serviceItem.Message.Title). Exception: $_");
			}

			try {
				[TraceLogging]::LogEvent([LoggingLevel]::Information, "ReleaseMessageTimer", "Main", "rmt144", "Posting notifications for $($serviceItem.Message.Id).");
				$notificationManager.SendMessage($serviceItem);
			}
			catch
			{
				[TraceLogging]::LogEvent([LoggingLevel]::Error, "ReleaseMessageTimer", "Main", "rmt182", "Couldn't post notificaction for [$($serviceItem.Message.Id)] $($serviceItem.Message.Title). Exception: $_");
			}
		}

		[TraceLogging]::LogEvent([LoggingLevel]::Information, "ReleaseMessageTimer", "Main", "rmt198", "Registering a synchronization heartbeat.");
		[ReleaseMessageHelper]::SetLastSyncTimestamp();

		[ImageStore]::ProcessImageStoreUpdates();
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

[TraceLogging]::LogEvent([LoggingLevel]::Information, "ReleaseMessageTimer", "Main", "rmt199", "All operations completed successfully.");