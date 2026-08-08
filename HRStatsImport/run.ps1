#region Modules
using module ..\Modules\M365ServiceHealthHubDB.psm1
using module ..\Modules\ConfigurationManager.psm1
using module ..\Modules\Logging.psm1
#endregion

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

#region Init
[TraceLogging]::InitializeCorrelationID();
$db = [M365ServiceHealthHubDB]::new();
$global:systemAlert = [NotificationManager]::new("SystemAlert");
#endregion

$component = "HRStatsImport";

$db = [M365ServiceHealthHubDB]::new($true);
$jobConfig = $db.GetComponentConfig($component);
$componentId = $($db.GetComponents().Rows | Where-Object InternalName -eq $component).ComponentId

if ($null -eq $jobConfig -or $jobConfig.enabled -eq $false) {
	[TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceUpdatesTimer", "Main", "hrs100", "[$component]: Job is disabled. Skipping.");
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

        [TraceLogging]::LogEvent([LoggingLevel]::Information, "Config", "Main", "hrs103", "Procesing HR data.");
        foreach ($forecast in $Request.Body)
        {
            try
            {
                $month = [datetime]$forecast.Month;
                [TraceLogging]::LogEvent([LoggingLevel]::Information, "HRStatsImport", "Main", "hrs130", "Adding data for $($month.ToString('Y')) - New hires: $($forecast.NewHires), Leavers: $($forecast.Leavers)");
                $db.AddLicenseHREmployeeForecast([datetime]$forecast.Month, ![string]::IsNullOrWhiteSpace($forecast.NewHires) ? $forecast.NewHires : 0, ![string]::IsNullOrWhiteSpace($forecast.Leavers) ? $forecast.Leavers : 0);
            }
            catch {
                [TraceLogging]::LogEvent([LoggingLevel]::Error, "HRStatsImport", "Main", "hrs181", "Couldn't add data. Exception: $_");
            }
        }

        [TraceLogging]::LogEvent([LoggingLevel]::Information, "HRStatsImport", "Main", "hrs199", "All operations completed.");

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

    } catch {

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
        
        $alert = [ServiceAlert]::new();
        $alert.Message = [PSCustomObject]@{
            Title = "Error occured while importing Employe forecast statistics"
            Type = "Realtime"
            Description = "<p>Couldn't import Employe forecast statistics</p><p>Exception: $($null -ne $_.Exception ? $_.Exception.ToString() : $_.ToString())</p>"
			Source= $component
            CommunicationID = ""
            CommunicationType = ""
            Timestamp = $timestamp
        };

        [NotificationManager]::SystemAlerts.SendMessage($alert);
    }
}

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [System.Net.HttpStatusCode]::OK
    Body = ""
})