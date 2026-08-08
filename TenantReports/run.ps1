#region Modules
using module ..\Modules\Utility.psd1
using module ..\Modules\Utility.psm1
using module ..\Modules\ConfigurationManager.psm1
using module ..\Modules\Logging.psm1
using module ..\Modules\TenantReports.psm1
using module ..\Modules\M365ServiceHealthHubDB.psm1
using module ..\Modules\ImageManager.psm1
#endregion

# Input bindings are passed in via param block.
param($Timer)

#region Init
[TraceLogging]::InitializeCorrelationID();
#endregion

$component = "TenantReports";

$db = [M365ServiceHealthHubDB]::new($true);
$jobConfig = $db.GetComponentConfig($component);
$componentId = $($db.GetComponents().Rows | Where-Object InternalName -eq $component).ComponentId

if ($null -eq $jobConfig -or $jobConfig.enabled -eq $false) {
	[TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceUpdatesTimer", "Main", "sut100", "[$component]: Job is disabled. Skipping.");
}
else {

    [TraceLogging]::LogEvent([LoggingLevel]::Information, "TenantReports", "Main", "trt100", "Processing tenant report jobs.");

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
		$tenantReports = [TenantReports]::new();
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "TenantReports", "Main", "trt103", "Retrieving license statistics.");
        $tenantReports.PersistLicenseStatistics();

        [TraceLogging]::LogEvent([LoggingLevel]::Information, "TenantReports", "Main", "trt103", "Retrieving monthly usage reports.");
        $tenantReports.PersistMonthlyUsageReport();

		[ImageStore]::ProcessImageStoreUpdates();

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
    }
}

[TraceLogging]::LogEvent([LoggingLevel]::Information, "TenantReports", "Main", "trt199", "All operations completed.");