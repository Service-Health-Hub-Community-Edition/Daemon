#region Modules
using module ..\Modules\Utility.psd1
using module ..\Modules\Utility.psm1
using module ..\Modules\ConfigurationManager.psm1
using module ..\Modules\RulesEngine.psm1
using module ..\Modules\Logging.psm1
using module ..\Modules\ServiceCommunication.psm1
using module ..\Modules\TaskManager\TaskManager.psm1
using module ..\Modules\NotificationManager\NotificationManager.psm1
using module ..\Modules\AzureBlobStorage.psm1
using module ..\Modules\M365ServiceHealthHubDB.psm1
#endregion

# Input bindings are passed in via param block.
param($Timer)

#region Init
[TraceLogging]::InitializeCorrelationID();
$global:systemAlert = [NotificationManager]::new("SystemAlert");
#endregion

$component = "ServiceHealthIssue";

$db = [M365ServiceHealthHubDB]::new($true);
$jobConfig = $db.GetComponentConfig($component);
$componentId = $($db.GetComponents().Rows | Where-Object InternalName -eq $component).ComponentId

if ($null -eq $jobConfig -or $jobConfig.enabled -eq $false) {
	[TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceIssuesTimer", "Main", "sit100", "[$component]: Job is disabled. Skipping.");
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

		$azureBlobStorage = $null;
		if (![string]::IsNullOrWhiteSpace([ConfigurationManager]::PostIncidentReviewStorage)) {
			$azureBlobStorage = [AzureBlobStorage]::new([ConfigurationManager]::PostIncidentReviewStorage);
		}

		$communicationType = [ServiceCommunicationType]::ServiceHealthIssue
		$messageTypeStr = "Service Health Issues"
		#endregion

		[TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceIssuesTimer", "Main", "sit101", "Retrieving last sync timestamp from the database.");
		$lastSyncTime = [ServiceCommunicationHelper]::GetLastSyncTime($communicationType);
		[TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceIssuesTimer", "Main", "sit102", "Last sync timestamp: $lastSyncTime.");
		[TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceIssuesTimer", "Main", "sit103", "Retrieving $messageTypeStr.");
		$serviceUpdates = [ServiceCommunicationHelper]::GetServiceCommunicationCollection([DateTime]"2000-01-01", $communicationType);
		[TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceIssuesTimer", "Main", "sit104", "Found $($serviceUpdates.Count) new items.");

		foreach ($serviceItem in $serviceUpdates) {		
			try {
				if (![ConfigurationManager]::GetTaskManagerConfigParameter("$([ConfigurationManager]::TaskManager).Disabled") -eq $false) {
					[TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceIssuesTimer", "Main", "sit130", "Task manager is enabled, processing the work item.");
					$taskManager.SetTask($serviceItem, $null);
					[TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceIssuesTimer", "Main", "sit131", "Work item $($serviceItem.WorkitemId) processed. Work item URL: $($serviceItem.WorkItemUrl).");

					if ($serviceItem.Message.status -eq "postIncidentReviewPublished") {
						try {
							[TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceIssuesTimer", "Main", "sit133", "Post incident review for $($serviceItem.Id) published. Attempting to retrieve...");
							$stream = $serviceItem.GetPostIncidentReport();
							[TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceIssuesTimer", "Main", "sit134", "Post incident review for $($serviceItem.Id) retrieved. Attaching to task...");
							$taskManager.AttachFile($serviceItem.WorkItemId, "$($serviceItem.Id)-PIR.docx", $stream);
							[TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceIssuesTimer", "Main", "sit135", "Post incident review for $($serviceItem.Id) successfully uploaded.");
							if ($null -ne $azureBlobStorage) {
								[TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceIssuesTimer", "Main", "sit136", "Uploading post incident review to Azure Blob Storage...");
								$azStorageFile = $azureBlobStorage.UploadFile("$($serviceItem.Id)-PIR.docx", $stream);
								[TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceIssuesTimer", "Main", "sit137", "Post incident review for $($serviceItem.Id) successfully uploaded.");
							}
						}
						catch {
							[TraceLogging]::LogEvent([LoggingLevel]::Error, "ServiceIssuesTimer", "Main", "sit138", "Couldn't upload post incident review for $($serviceItem.Id). Exception: $_");
						}
					}
				}
			}
			catch {
				[TraceLogging]::LogEvent([LoggingLevel]::Error, "ServiceIssuesTimer", "Main", "sit181", "Couldn't process task for [$($serviceItem.Message.Id)] $($serviceItem.Message.Title). Exception: $_");
			}

			$serviceItem.Update()

			$serviceItem.Index();

			try {
				[TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceIssuesTimer", "Main", "sit144", "Posting notifications for $($serviceItem.Message.Id).");
				$notificationManager.SendMessage($serviceItem);
			}
			catch
			{
				[TraceLogging]::LogEvent([LoggingLevel]::Error, "ServiceIssuesTimer", "Main", "sut182", "Couldn't post notificaction for [$($serviceItem.Message.Id)] $($serviceItem.Message.Title). Exception: $_");
			}
		}

		[TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceIssuesTimer", "Main", "sit198", "Registering a synchronization heartbeat.");
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

[TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceIssuesTimer", "Main", "sit199", "All operations completed successfully.");