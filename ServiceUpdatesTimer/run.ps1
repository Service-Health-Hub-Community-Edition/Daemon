#region Modules
using module ..\Modules\Utility.psd1
using module ..\Modules\Utility.psm1
using module ..\Modules\ConfigurationManager.psm1
using module ..\Modules\RulesEngine.psm1
using module ..\Modules\Logging.psm1
using module ..\Modules\ServiceCommunication.psm1
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

$component = "ServiceUpdateMessage";

$db = [M365ServiceHealthHubDB]::new($true);
$jobConfig = $db.GetComponentConfig($component);
$componentId = $($db.GetComponents().Rows | Where-Object InternalName -eq $component).ComponentId

if ($null -eq $jobConfig -or $jobConfig.enabled -eq $false) {
	[TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceUpdatesTimer", "Main", "sut100", "[$component]: Job is disabled. Skipping.");
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

		$communicationType = [ServiceCommunicationType]::ServiceUpdateMessage
		$messageTypeStr = "Service Update Messages"
		#endregion

		[TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceUpdatesTimer", "Main", "sut101", "Retrieving last sync timestamp from the database.");
		$lastSyncTime = [ServiceCommunicationHelper]::GetLastSyncTime($communicationType);
		[TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceUpdatesTimer", "Main", "sut102", "Last sync timestamp: $lastSyncTime.");
		[TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceUpdatesTimer", "Main", "sut103", "Retrieving $messageTypeStr.");
		$serviceUpdates = [ServiceCommunicationHelper]::GetServiceCommunicationCollection([DateTime]"2000-01-01", $communicationType);
		[TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceUpdatesTimer", "Main", "sut104", "Found $($serviceUpdates.Count) new items.");

		foreach ($serviceItem in $serviceUpdates) {		
			try {
				if (![ConfigurationManager]::GetTaskManagerConfigParameter("$([ConfigurationManager]::TaskManager).Disabled") -eq $false) {
					[TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceUpdatesTimer", "Main", "sut130", "Task manager is enabled, processing the work item.");
					$taskManager.SetTask($serviceItem, $null);

					[TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceUpdatesTimer", "Main", "sut131", "Work item $($serviceItem.WorkitemId) processed. Work item URL: $($serviceItem.WorkItemUrl).");

					$roadmapIds = $serviceItem.GetRoadmapIds();
					foreach ($roadmapId in $roadmapIds) {
						$rmItem = $null;
						$rmItemFound = $false
						try {
							$rmItem = [RoadmapCommunication]::new($roadmapId.Trim(), [RoadmapCommunicationSource]::Database);
							[TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceUpdatesTimer", "Main", "sut132", "Work item for Roadmap Id $($roadmapId.Trim()) found. Work item Id: $($rmItem.WorkItemId).");
							$rmItemFound = $true;
						}
						catch {
							[TraceLogging]::LogEvent([LoggingLevel]::Error, "ServiceUpdatesTimer", "Main", "sut133", "Work item for Roadmap Id $($roadmapId.Trim()) could not be retrieved. Exception: $_");
						}
				
						if ($rmItemFound -eq $true) {
							[TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceUpdatesTimer", "Main", "sut134", "Linking work items $($serviceItem.WorkItemId) and $($rmItem.WorkItemId).");
							$taskManager.LinkTasks($serviceItem, $rmItem);
						}
						else {
							[TraceLogging]::LogEvent([LoggingLevel]::Warning, "ServiceUpdatesTimer", "Main", "sut138", "Work item for Roadmap Id $($roadmapId.Trim()) not found. Skipping.");
						}
					}
				}
			}
			catch {
				[TraceLogging]::LogEvent([LoggingLevel]::Error, "ServiceUpdatesTimer", "Main", "sut181", "Couldn't process task for [$($serviceItem.Message.Id)] $($serviceItem.Message.Title). Exception: $_");
			}

			$serviceItem.Update()

			$serviceItem.Index();

			try {
				[TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceUpdatesTimer", "Main", "sut144", "Posting notifications for $($serviceItem.Message.Id).");
				$notificationManager.SendMessage($serviceItem);
			}
			catch
			{
				[TraceLogging]::LogEvent([LoggingLevel]::Error, "ServiceUpdatesTimer", "Main", "sut182", "Couldn't post notificaction for [$($serviceItem.Message.Id)] $($serviceItem.Message.Title). Exception: $_");
			}	
		}

		[TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceUpdatesTimer", "Main", "sut198", "Registering a synchronization heartbeat.");
		[ServiceCommunicationHelper]::SetLastSyncTimestamp($communicationType);
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
[TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceUpdatesTimer", "Main", "sut199", "All operations completed successfully.");