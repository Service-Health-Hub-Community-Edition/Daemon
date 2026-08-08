#region Modules
using module ..\Modules\M365ServiceHealthHubDB.psm1
using module ..\Modules\ImageManager.psm1
using module ..\Modules\Logging.psm1
#endregion

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

#region Init
[TraceLogging]::InitializeCorrelationID();
#endregion

[TraceLogging]::LogEvent([LoggingLevel]::Information, "Config", "Main", "cfg103", "Performing Microsoft Service Health Hub configuration.");

$db = [M365ServiceHealthHubDB]::new();
$db.PerformSchemaCheck();

[ImageStore]::ProcessImageStoreUpdates();

[TraceLogging]::LogEvent([LoggingLevel]::Information, "Config", "Main", "cfg199", "All operations completed.");

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [System.Net.HttpStatusCode]::OK
    Body = ""
})