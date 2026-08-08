#region Modules
using module ..\Modules\Utility.psd1
using module ..\Modules\Utility.psm1
using module ..\Modules\ConfigurationManager.psm1
using module ..\Modules\RulesEngine.psm1
using module ..\Modules\Logging.psm1
using module ..\Modules\RoadmapCommunication.psm1
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

$component = "RoadmapCommunication";

$db = [M365ServiceHealthHubDB]::new($true);
$jobConfig = $db.GetComponentConfig($component);
$componentId = $($db.GetComponents().Rows | Where-Object InternalName -eq $component).ComponentId

if ($null -eq $jobConfig -or $jobConfig.enabled -eq $false) {
	[TraceLogging]::LogEvent([LoggingLevel]::Information, "RoadmapNotificationsTimer", "Main", "sit100", "[$component]: Job is disabled. Skipping.");
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

		$rehydrateRoadmapItems = [Utility]::ParseBooleanValue([ConfigurationManager]::RehydrateRoadmapItems);
		#endregion

		[TraceLogging]::LogEvent([LoggingLevel]::Information, "RoadmapNotificationsTimer", "Main", "rnt101", "Retrieving last sync timestamp from the database.");
		$lastSyncTime = [RoadmapCommunicationHelper]::GetLastSyncTime()
		[TraceLogging]::LogEvent([LoggingLevel]::Information, "RoadmapNotificationsTimer", "Main", "rnt102", "Last sync timestamp: $lastSyncTime.");
		[TraceLogging]::LogEvent([LoggingLevel]::Information, "RoadmapNotificationsTimer", "Main", "rnt103", "Initializing roadmap cache.");
		$Global:RoadmapCache = [RoadmapCache]::new()
		$roadmapItems = $Global:RoadmapCache.GetRoadmapItems($lastSyncTime)
		[TraceLogging]::LogEvent([LoggingLevel]::Information, "RoadmapNotificationsTimer", "Main", "rnt104", "$($roadmapItems.Count) items retrieved since last sync.");

		foreach ($rmItem in $roadmapItems) {
			$rmItemInitSuccess = $true
			try {
				[TraceLogging]::LogEvent([LoggingLevel]::Information, "RoadmapNotificationsTimer", "Main", "rnt110", "Processing communication [$($rmItem.Id)] $($rmItem.Title).");
				$roadmapItem = [RoadmapCommunication]::new($rmItem.Id);
			}
			catch {
				[TraceLogging]::LogEvent([LoggingLevel]::Error, "RoadmapNotificationsTimer", "Main", "rnt111", "Exception caught: $_");
				$rmItemInitSuccess = $false
			}
	
			if ($rmItemInitSuccess) {
				try {
			
					if (![string]::IsNullOrWhiteSpace($roadmapItem.Id)) {
						[TraceLogging]::LogEvent([LoggingLevel]::Information, "RoadmapNotificationsTimer", "Main", "rnt114", "Communication $($rmItem.Id) found in the database. Retrieving the newest information from the API.");
						$roadmapItem.GetNewestVersionFromAPI();
					}
					else {
						[TraceLogging]::LogEvent([LoggingLevel]::Information, "RoadmapNotificationsTimer", "Main", "rnt117", "Communication $($rmItem.Id) not found in the database. Retrieving the communication from the API.");
						$roadmapItem.GetRoadmapCommunicationFromAPI($rmItem.Id);
					}

					if ($roadmapItem.UpdatesAvailable) {
						try {
							if (!$rehydrateRoadmapItems) {
								if (![ConfigurationManager]::GetTaskManagerConfigParameter("$([ConfigurationManager]::TaskManager).Disabled") -eq $false) {
									[TraceLogging]::LogEvent([LoggingLevel]::Information, "RoadmapNotificationsTimer", "Main", "rnt130", "Task manager is enabled, processing the work item.");
									$taskManager.SetTask($roadmapItem, $null);
									[TraceLogging]::LogEvent([LoggingLevel]::Information, "RoadmapNotificationsTimer", "Main", "rnt131", "Work item $($roadmapItem.WorkitemId) processed. Work item URL: $($roadmapItem.WorkItemUrl).");
								}
	
								$roadmapItem.Update();
							}
							else {
								[TraceLogging]::LogEvent([LoggingLevel]::Information, "RoadmapNotificationsTimer", "Main", "rnt145", "Rehydrating $($roadmapItem.Message.Id).");
								$roadmapItem.Update();
							}

							$roadmapItem.Index();
						}
						catch {
							[TraceLogging]::LogEvent([LoggingLevel]::Error, "RoadmapNotificationsTimer", "Main", "rnt181", "Couldn't process task for [$($roadmapItem.Message.Id)] $($roadmapItem.Message.Title). Exception: $_");
						}

						if (!$rehydrateRoadmapItems) {
							try {
								[TraceLogging]::LogEvent([LoggingLevel]::Information, "RoadmapNotificationsTimer", "Main", "rnt144", "Posting notifications for $($roadmapItem.Message.Id).");
								$notificationManager.SendMessage($roadmapItem);
							}
							catch
							{
								[TraceLogging]::LogEvent([LoggingLevel]::Error, "RoadmapNotificationsTimer", "Main", "rnt182", "Couldn't post notificaction for [$($serviceItem.Message.Id)] $($serviceItem.Message.Title). Exception: $_");
							}
						}					
					}
					else {
						[TraceLogging]::LogEvent([LoggingLevel]::Information, "RoadmapNotificationsTimer", "Main", "rnt151", "Communication $($rmItem.Id) does not contain any new updates. Skipping.");
					}
				}
				catch {
					[TraceLogging]::LogEvent([LoggingLevel]::Error, "RoadmapNotificationsTimer", "Main", "rnt181", "Couldn't post the message [$($roadmapItem.Message.Id)] $($roadmapItem.Message.Title). Exception: $_");
				}
			}
		}

		[TraceLogging]::LogEvent([LoggingLevel]::Information, "RoadmapNotificationsTimer", "Main", "rnt198", "Registering a synchronization heartbeat.");
		[RoadmapCommunicationHelper]::SetLastSyncTimestamp()
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

[TraceLogging]::LogEvent([LoggingLevel]::Information, "RoadmapNotificationsTimer", "Main", "rnt199", "All operations completed successfully.");