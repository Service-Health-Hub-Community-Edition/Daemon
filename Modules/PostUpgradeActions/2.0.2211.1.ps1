using module ..\Logging.psm1
using module ..\SqlConnector.psm1
using module ..\ConfigurationManager.psm1
using module ..\RoadmapCommunication.psm1
using module ..\TaskManager\TaskManager.psm1

$version = "2.0.2211.1";
$global:M365HHDBSchemaCheckCompleted = $true; # disable schema upgrade during post-upgrade procedure

function Convert-LegacyRoadmapItems
{
    $component = "RoadmapCommunication";

    [TraceLogging]::LogEvent(
        [LoggingLevel]::Information,
        "Upgrade",
        $version, "upg2211-1-0012",
        "Migrating legacy roadmap communications.");

    $sqlHelper = [SqlConnector]::new([ConfigurationManager]::ConnectionString);
    $query = "SELECT [ID] FROM [dbo].[AllRoadmapCommsDetailed] WHERE [Status] IS NULL"
    $res = $sqlHelper.GetParametrizedDataSet($query, $null, -1)
    $roadmapCache = [RoadmapCache]::new();


    if ($null -ne $res -and $null -ne $res.Tables -and $res.Tables.Count -gt 0)
    {
        $taskManager = [TaskManager]::CreateInstance(
            [ConfigurationManager]::TaskManager,
            $component
        );
        
        [TraceLogging]::LogEvent(
            [LoggingLevel]::Information,
            "Upgrade",
            $version, "upg2211-1-0013",
            "$($res.Tables[0].Rows.Count) legacy roadmap items found. Processing.");

        $count = 0;
        foreach ($record in $res.Tables[0].Rows)
        {
            $roadmapItems = $roadmapCache.RoadmapItems | Where-Object Id -eq $record.ID

            if ($roadmapItems.Count -gt 0)
            {
                [TraceLogging]::LogEvent(
                    [LoggingLevel]::Information,
                    "Upgrade",
                    $version, "upg2211-1-0014",
                    "Processing roadmap item $($roadmapItems[0].Id), item $count/$($res.Tables[0].Rows.Count).");

                $item = [RoadmapCommunication]::new($roadmapItems[0].Id);
                $item.GetRoadmapCommunicationFromAPI($roadmapItems[0].Id);
                if (![string]::IsNullOrWhiteSpace($item.WorkItemId))
                {
                    try{
                        $taskManager.SetTask($item, $null);
                    } catch {
                        [TraceLogging]::LogEvent(
                            [LoggingLevel]::Error,
                            "Upgrade",
                            $version, "upg2211-1-0015",
                            "Couldn't update task for roadmap item $($roadmapItems[0].Id). Exception: $_");
                    }
                }
                $item.Update();
            }

            $count++
        }
    }
}

[TraceLogging]::LogEvent(
    [LoggingLevel]::Information,
    "Upgrade",
    $version, "upg2211-1-0000",
    [string]::Format(
        "{0}: Entering post-upgrade procedure.",
        $version));

[TraceLogging]::LogEvent(
    [LoggingLevel]::Information,
    "Upgrade",
    $version, "upg2211-1-0001",
    [string]::Format(
        "{0}: Migrating legacy roadmap items.",
        $version));

Convert-LegacyRoadmapItems

[TraceLogging]::LogEvent(
    [LoggingLevel]::Information,
    "Upgrade",
    $version, "upg2211-1-00ff",
    [string]::Format(
        "{0}: Exiting post-upgrade procedure.",
        $version));