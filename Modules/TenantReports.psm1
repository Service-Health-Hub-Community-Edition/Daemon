using module .\Logging.psm1
using module .\AuthManager.psm1
using module .\AuthManagerHelper.psm1
using module .\ConfigurationManager.psm1
using module .\M365ServiceHealthHubDB.psm1

class TenantReports {
    hidden [AuthManager] $AuthManager = $null;
    hidden [M365ServiceHealthHubDB]$m_m365shhdb = [M365ServiceHealthHubDB]::new();
    [System.Object] $LicenseStatistics = $null;
    [System.Object] $MonthlyUsageReport = $null;

    TenantReports() {
        $authConfigKey = [ConfigurationManager]::GraphApiAuthConfig;
        if ([string]::IsNullOrWhiteSpace($authConfigKey))
        {
            $this.AuthManager = [AuthManagerHelper]::CreateInstance("https://graph.microsoft.com");
        } else {
            $authConfigJson = [ConfigurationManager]::GetSecret($authConfigKey);
            $authConfig = ConvertFrom-Json $authConfigJson
            $this.AuthManager = [AuthManager]::new(
                $authConfig.ClientId,
                $authConfig.ClientSecret,
                $authConfig.TenantDomain,
                "https://graph.microsoft.com")
        }
    }

    hidden [System.Object]GetLicenseStatistics() {
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "TenantReports", "LicenseStatistics", "tr270", "Entering method TenantReports.GetLicenseStatistics()");
        
        $uri = "https://graph.microsoft.com/v1.0/subscribedSkus";
        $Headers = @{
            Authorization = [string]::Format("{0} {1}",
                $this.AuthManager.Token.token_type,
                $this.AuthManager.Token.access_token);
        }

        $res = $null;
        try {
            [TraceLogging]::LogEvent([LoggingLevel]::Information, "TenantReports", "LicenseStatistics", "tr273", "Retrieving license statistics.");
            $res = Invoke-RestMethod -Uri $uri -Method GET -Headers $Headers
            [TraceLogging]::LogEvent([LoggingLevel]::Information, "TenantReports", "LicenseStatistics", "tr274", "Successfully retrieved license statistics.");
        }
        catch {
            [TraceLogging]::LogEvent([LoggingLevel]::Error, "TenantReports", "LicenseStatistics", "tr275", "Could not retrieve license statistics from the tenant. Exception: $($_.Exception). Stack trace: $($_.ScriptStackTrace)"); 
        }
        
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "TenantReports", "LicenseStatistics", "tr27f", "Exiting method TenantReports.GetLicenseStatistics()");
        return $res.value;
    }

    [void]PersistLicenseStatistics() {
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "TenantReports", "LicenseStatistics", "tr370", "Entering method TenantReports.PersistLicenseStatistics()");

        if ($null -eq $this.LicenseStatistics) {
            $this.LicenseStatistics = $this.GetLicenseStatistics();
        }

        if ($null -ne $this.LicenseStatistics) {
            foreach ($licenseStat in $this.LicenseStatistics) {
                [TraceLogging]::LogEvent([LoggingLevel]::Information, "TenantReports", "LicenseStatistics", "tr370", "Persisting license statistics for SKU $($licenseStat.skuPartNumber)");
                
                $this.m_m365shhdb.AddLicenseStatistics(
                    $licenseStat.skuPartNumber,
                    $licenseStat.consumedUnits,
                    $licenseStat.prepaidUnits.enabled,
                    $licenseStat.prepaidUnits.suspended,
                    $licenseStat.prepaidUnits.warning
                );
            }
        }
        else {
            [TraceLogging]::LogEvent([LoggingLevel]::Warning, "TenantReports", "LicenseStatistics", "tr36f", "No license statistics were obtained. Skipping.");
        }

        [TraceLogging]::LogEvent([LoggingLevel]::Information, "TenantReports", "LicenseStatistics", "tr37f", "Exiting method TenantReports.PersistLicenseStatistics()");
    }

     [System.Object]GetMonthlyUsageReport() 
    {
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "TenantReports", "MonthlyUsage", "tr390", "Entering method TenantReports.GetMonthlyUsageReport()");

        $uri = "https://graph.microsoft.com/v1.0/reports/getOffice365ServicesUserCounts(period='D30')";
        $Headers = @{
            Authorization = [string]::Format("{0} {1}",
                $this.AuthManager.Token.token_type,
                $this.AuthManager.Token.access_token);
        }

        $sourceObj = $null;
        try {
            [TraceLogging]::LogEvent([LoggingLevel]::Information, "TenantReports", "MonthlyUsage", "tr392", "Retrieving monthly usage statistics.");
            # Get the count of users by activity type and service.
            # https://docs.microsoft.com/en-us/graph/api/reportroot-getoffice365servicesusercounts?view=graph-rest-1.0
            $result = Invoke-RestMethod -Method GET -Headers $headers -Uri $uri

            [TraceLogging]::LogEvent([LoggingLevel]::Information, "TenantReports", "MonthlyUsage", "tr394", "Statistics retrieved. Deserializing object.");                                                                                
            $report = $result.Substring(3)
            $sourceObj = $report | ConvertFrom-Csv  
            [TraceLogging]::LogEvent([LoggingLevel]::Information, "TenantReports", "MonthlyUsage", "tr396", "Successfully retrieved monthly usage statistics.");
        }
        catch {
            [TraceLogging]::LogEvent([LoggingLevel]::Error, "TenantReports", "MonthlyUsage", "tr397", "Could not retrieve monthly usage statistics from the tenant. Exception: $($_.Exception). Stack trace: $($_.ScriptStackTrace)"); 
        }
                                                                                                                          
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "TenantReports", "MonthlyUsage", "tr398", "Retrieving list of services.");
        $dataSourceIdentifiers = $sourceObj | Get-Member | Where-Object MemberType -eq "NoteProperty" | Where-Object Name -like "* active" | Select-Object -ExpandProperty Name
        $services = @()
        foreach ($parameter in $dataSourceIdentifiers) {
            $service = [string]::Empty;
            if ($parameter.EndsWith(" Inactive")) {
                $service = $parameter.Substring(0, $parameter.Length - 9)
            }
            else {
                $service = $parameter.Substring(0, $parameter.Length - 7)
            }

            if (!$services.Contains($service)) {
                $services += $service
            }
        }

        [TraceLogging]::LogEvent([LoggingLevel]::Information, "TenantReports", "MonthlyUsage", "tr39a", "Generating dataset.");
        $serviceStats = @()
        foreach ($service in $services) {
            $active = $sourceObj."$service Active"
            $inactive = $sourceObj."$service Inactive"
            $serviceStat = New-Object -TypeName PSObject
            Add-Member -InputObject $serviceStat -NotePropertyName Service -NotePropertyValue $service
            Add-Member -InputObject $serviceStat -NotePropertyName Active -NotePropertyValue $active
            Add-Member -InputObject $serviceStat -NotePropertyName Inactive -NotePropertyValue $inactive
            Add-Member -InputObject $serviceStat -NotePropertyName ReportDate -NotePropertyValue $sourceObj.'Report Refresh Date'
            $serviceStats += $serviceStat
        }

        [TraceLogging]::LogEvent([LoggingLevel]::Information, "TenantReports", "MonthlyUsage", "tr39f", "Exiting method TenantReports.GetMonthlyUsageReport()");
        return $serviceStats
    }

    [void]PersistMonthlyUsageReport() {
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "TenantReports", "MonthlyUsage", "tr3a0", "Entering method TenantReports.PersistMonthlyUsageReport()");

        if ($null -eq $this.MonthlyUsageReport) {
            $this.MonthlyUsageReport = $this.GetMonthlyUsageReport();
        }

        if ($null -ne $this.MonthlyUsageReport) {
            foreach ($mauStats in $this.MonthlyUsageReport) {
                [TraceLogging]::LogEvent([LoggingLevel]::Information, "TenantReports", "MonthlyUsage", "tr3a1", "Persisting monthly usage report for $($mauStats.Service)");
                
                $this.m_m365shhdb.AddMonthlyActiveUsersStatistics(
                    $mauStats.Service,
                    $mauStats.Active,
                    $mauStats.Inactive,
                    $mauStats.ReportDate
                );
            }
        }
        else {
            [TraceLogging]::LogEvent([LoggingLevel]::Warning, "TenantReports", "MonthlyUsage", "tr3aa", "No monthly usage reports were obtained. Skipping.");
        }

        [TraceLogging]::LogEvent([LoggingLevel]::Information, "TenantReports", "MonthlyUsage", "tr3af", "Exiting method TenantReports.PersistMonthlyUsageReport()");
    }
}