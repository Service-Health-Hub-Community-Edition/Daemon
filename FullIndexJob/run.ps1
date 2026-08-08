#region Modules
using module ..\Modules\Utility.psd1
using module ..\Modules\Utility.psm1
using module ..\Modules\ConfigurationManager.psm1
using module ..\Modules\Logging.psm1
using module ..\Modules\Services\GraphConnector.psm1
using module ..\Modules\BaseMessage.psm1
using module ..\Modules\ServiceCommunication.psm1
using module ..\Modules\RoadmapCommunication.psm1
# using module ..\Modules\AzureUpdates.psm1
using module ..\Modules\D365PowerPlatformRelease.psm1
using module ..\Modules\NotificationManager\NotificationManager.psm1
using module ..\Modules\M365ServiceHealthHubDB.psm1
#endregion

# Input bindings are passed in via param block.
param($Timer)

#region Init
[TraceLogging]::InitializeCorrelationID();
$global:systemAlert = [NotificationManager]::new("SystemAlert");
#endregion

[TraceLogging]::LogEvent([LoggingLevel]::Information, "FullIndexJob", "Main", "fi01a", "Entering full index job.");

$global:ServiceHealthHubGraphConnector = [GraphConnector]::new();

if ($global:ServiceHealthHubGraphConnector.Enabled)
{
	[TraceLogging]::LogEvent([LoggingLevel]::Information, "FullIndexJob", "Main", "fi027", "Graph Connector is enabled and configured.");

	if ($global:ServiceHealthHubGraphConnector.PermissionsChanged())
	{
		# re-index items
		# to be considered - should we re-index all items without resetting indexed flag? If so, how do we handle errors / function timeouts
		# if we reset index flag, how do we handle items that which are not available in source systems anymore?
		[TraceLogging]::LogEvent([LoggingLevel]::Information, "FullIndexJob", "Main", "fi031", "Permissions are changed, resetting index flag on all indexed items.");

		$global:ServiceHealthHubGraphConnector.ResetIndexFlag(); # this will set index flag to -1 for all indexed items and force re-indexing

		[TraceLogging]::LogEvent([LoggingLevel]::Information, "FullIndexJob", "Main", "fi033", "Copying permissions to the ACL cache.");
		$global:ServiceHealthHubGraphConnector.CopyPermissionsToCache(); # copy current ACLs to cache

		[TraceLogging]::LogEvent([LoggingLevel]::Information, "FullIndexJob", "Main", "fi035", "Persisting Graph Connector.");
		$global:ServiceHealthHubGraphConnector.SetSearchConnector(); # store Graph Connector object to the database, persist changed ACLs
	}

	# re-index existing items

	[TraceLogging]::LogEvent([LoggingLevel]::Information, "FullIndexJob", "Main", "fi041", "Retrieving items marked for re-indexing.");
	$db = [M365ServiceHealthHubDB]::new();
	$itemsToReindex = $db.GetServiceCommunicationsForReindexing();

	[TraceLogging]::LogEvent([LoggingLevel]::Information, "FullIndexJob", "Main", "fi045", "Found $($itemsToReindex.Rows.Count) items to re-index.");
	foreach ($item in $itemsToReindex.Rows)
	{
		[TraceLogging]::LogEvent([LoggingLevel]::Information, "FullIndexJob", "Main", "fi04a", "Processing item $($item.Id).");
		$messageToIndex = $null;
		switch ($item.Type)
		{
			"ServiceUpdateMessage" { $messageToIndex = [ServiceUpdateMessage]::new($item.Id, [ServiceCommunicationSource]::Database, $null) }
			"ServiceHealthIssue" { $messageToIndex = [ServiceHealthIssue]::new($item.Id, [ServiceCommunicationSource]::Database, $null) }
			"RoadmapCommunication" { $messageToIndex = [RoadmapCommunication]::new($item.Id, [RoadmapCommunicationSource]::Database) }
			"D365PowerPlatformRelease" { $messageToIndex = [D365PowerPlatformRelease]::new($item.Id, [D365PowerPlatformReleaseSource]::Database) }
			default { [TraceLogging]::LogEvent([LoggingLevel]::Warning, "FullIndexJob", "Main", "fi200", "Unknown item type: $($item.Type). Skipping.") }
		}

		if ($null -ne $messageToIndex)
		{
			[TraceLogging]::LogEvent([LoggingLevel]::Information, "FullIndexJob", "Main", "fi04c", "Item $($item.Id) successfully initialized, indexing.");
			$messageToIndex.Index();
		}
	}

	[TraceLogging]::LogEvent([LoggingLevel]::Information, "FullIndexJob", "Main", "fi061", "Retrieving non-indexed items.");
	# index items which are missed during the synchronization
	# initialize non-indexed items collection
	$messagesToIndex = [System.Collections.Generic.List[BaseMessage]]::new();

	# process missing Message Center communications
	[TraceLogging]::LogEvent([LoggingLevel]::Information, "FullIndexJob", "Main", "fi063", "Processing Message Center communications.");
	$mc = [ServiceCommunicationHelper]::GetServiceCommunicationCollection([DateTime]"2000-01-01", [ServiceCommunicationType]::ServiceUpdateMessage, [ServiceCommunicationSource]::API, $null, $true) | Where-Object { $_.Indexed -eq 0 };
	[TraceLogging]::LogEvent([LoggingLevel]::Information, "FullIndexJob", "Main", "fi065", "$($mc.Count) items found." + $($mc.Count -gt 0 ? " Adding." : " Skipping."));
	foreach ($msg in $mc)
	{
		$messagesToIndex.Add($msg);
	}

	# process missing Service Health items
	[TraceLogging]::LogEvent([LoggingLevel]::Information, "FullIndexJob", "Main", "fi073", "Processing Service Health items.");
	$serviceHealth = [ServiceCommunicationHelper]::GetServiceCommunicationCollection([DateTime]"2000-01-01", [ServiceCommunicationType]::ServiceHealthIssue, [ServiceCommunicationSource]::API, $null, $true) | Where-Object { $_.Indexed -eq 0 };
	[TraceLogging]::LogEvent([LoggingLevel]::Information, "FullIndexJob", "Main", "fi075", "$($serviceHealth.Count) items found." + $($serviceHealth.Count -gt 0 ? " Adding." : " Skipping."));
	foreach ($msg in $serviceHealth)
	{
		$messagesToIndex.Add($msg);
	}
	
	# process missing Roadmap items
	[TraceLogging]::LogEvent([LoggingLevel]::Information, "FullIndexJob", "Main", "fi083", "Processing Roadmap items.");
	$Global:RoadmapCache = [RoadmapCache]::new()
	$roadmapItems = $Global:RoadmapCache.GetRoadmapItems([DateTime]"2000-01-01")
	[TraceLogging]::LogEvent([LoggingLevel]::Information, "FullIndexJob", "Main", "fi085", "$($roadmapItems.Count) items found." + $($roadmapItems.Count -gt 0 ? " Adding." : " Skipping."));
	foreach ($msg in $roadmapItems)
	{
		$roadmapItem = [RoadmapCommunication]::new($msg.Id);
		if ($roadmapItem.ExistsInDatabase -and $roadmapItem.Indexed -eq 0)
		{
			$messagesToIndex.Add($roadmapItem);
		}
		
	}

	# process missing Dynamics 365 and Power Platform Release items
	[TraceLogging]::LogEvent([LoggingLevel]::Information, "FullIndexJob", "Main", "fi093", "Processing Dynamics 365 and Power Platform Release items.");
	$d365pp = [D365PowerPlatformReleaseHelper]::GetD365PowerPlatformReleaseCollection($false) | Where-Object { $_.Indexed -eq 0 };
	[TraceLogging]::LogEvent([LoggingLevel]::Information, "FullIndexJob", "Main", "fi095", "$($d365pp.Count) items found." + $($d365pp.Count -gt 0 ? " Adding." : " Skipping."));
	foreach ($msg in $d365pp)
	{
		$messagesToIndex.Add($msg);
	}

	# collection is initialized, now index all items
	[TraceLogging]::LogEvent([LoggingLevel]::Information, "FullIndexJob", "Main", "fi0a2", "Collection initialized. Items found: $($messagesToIndex.Count).");
	$c = 0;
	foreach ($msg in $messagesToIndex)
	{
		$percCompleted = [Math]::Round(($c / $messagesToIndex.Count) * 100, 2);
		[TraceLogging]::LogEvent([LoggingLevel]::Information, "FullIndexJob", "Main", "fi0a2", "Indexing item $($msg.Id), $c/$($messagesToIndex.Count), $percCompleted%.");
		$msg.Index();
		$c++;
	}
}

[TraceLogging]::LogEvent([LoggingLevel]::Information, "FullIndexJob", "Main", "fifff", "All operations completed successfully. Exiting.");