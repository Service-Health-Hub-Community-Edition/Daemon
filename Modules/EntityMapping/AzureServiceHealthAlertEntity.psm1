using module ..\Utility.psd1
using module ..\Utility.psm1
using module ..\Logging.psm1
using module ..\BaseMessage.psm1
using module .\BaseEntity.psm1
using module ..\Services\AzureLanguageServices.psm1

class AzureServiceHealthAlertEntity: BaseEntity
{
    AzureServiceHealthAlertEntity(
        [BaseMessage]$Message
    ): base($Message)
    {
        
    }

    [void]Initialize(
        [BaseMessage]$Message
    )
    {
        ([BaseEntity]$this).Initialize($Message);

        if ($null -ne $Message.Message)
        {
            $textSummarization = [TextSummarization]::new();

            $title = [Utility]::NormalizeValue($Message.Message.data.alertContext.properties.trackingId) + ": " + 
                    [Utility]::NormalizeValue($Message.Message.data.alertContext.properties.title);

            $msg = $Message.Message.data.alertContext.properties.communication;
            $description = [regex]::Replace($msg, '(?<=<p>)\\[.+?\\](?=</p>)', '<b>$&</b>');
            $history = [regex]::Replace($msg, '(?<=<p>)\\[.+?\\](?=</p>)', '<b>$&</b>');

            $notificationTitle = $title;

            $severity = $Message.Message.data.essentials.Severity;
            
            $tags = @();
            $is = $null;
            if ($null -ne $Message.Message.data.alertContext.properties.impactedServices -and $Message.Message.data.alertContext.properties.impactedServices.GetType().Name -eq "String")
            {
                $is = $Message.Message.data.alertContext.properties.impactedServices | ConvertFrom-Json
            } else {
                $is = $Message.Message.data.alertContext.properties.impactedServices
            }
            $services = $is | Select-Object -ExpandProperty ServiceName -Unique;
            $regions = $is.ImpactedRegions | Select-Object -ExpandProperty RegionName -Unique;
            $impactedServices = $Message.Message.data.alertContext.properties.impactedServicesTableRows;
            $tags += $Message.Message.data.alertContext.status;
            foreach ($service in $services) { $tags += $service };
            foreach ($region in $regions) { $tags += $region };
            $tags += $Message.Message.data.alertContext.properties.impactType;
            $tagsJoined = $tags -join ' • ';
            
            $subscriptions = @();
            foreach ($targetId in $Message.Message.data.essentials.alertTargetIds)
            {
                $targetIdComponents = $targetId.ToString().Split("/");
                if ($targetIdComponents -ge 3 -and $targetIdComponents[1] -eq "subscriptions")
                {
                    $subscriptions += $targetIdComponents[2];
                }

            }

            $summary = $null
            try {
                $summary = $textSummarization.GetSummary($Message.Message.data.alertContext.properties.trackingId, [Utility]::ConvertToPlainText($description, $true));
            }
            catch {
                [TraceLogging]::LogEvent([
                    LoggingLevel]::Error, 
                    "AzureServiceHealthAlertEntity", "Summary", "aze371", "Couldn't process communication summary. Details: $_");
            }
            
            
            $this.m_properties.Add("Title", $title);
            $this.m_properties.Add("NotificationTitle", $notificationTitle);
            $this.m_properties.Add("Description", $description);
            $this.m_properties.Add("Summary", $summary);
            $this.m_properties.Add("History", $history);
            $this.m_properties.Add("Severity", $severity);
            $this.m_properties.Add("ServicesArray", $services);
            $this.m_properties.Add("Services", $($services -join ', '));
            $this.m_properties.Add("ImpactedServicesDescription", $impactedServices);
            $this.m_properties.Add("Subscriptions", $subscriptions);
            $this.m_properties.Add("SubscriptionsTextList", $($subscriptions -join ', '));
            $this.m_properties.Add("TagsArray", $tags);
            $this.m_properties.Add("Tags", $tagsJoined);
            $this.m_properties.Add("ADOTags", $($tags -join ';'));
            $this.m_properties.Add("Stage", [Utility]::NormalizeValue($Message.Message.data.alertContext.properties.stage));
            $this.m_properties.Add("IsResolved", ![string]::IsNullOrWhiteSpace($Message.Message.data.alertContext.properties.impactMitigationTime));
            $this.m_properties.Add("Type", [Utility]::NormalizeValue($Message.Message.data.alertContext.properties.incidentType));
            $this.m_properties.Add("ImpactType", [Utility]::NormalizeValue($Message.Message.data.alertContext.properties.impactType));
            $this.m_properties.Add("Region", $($regions -join ', '));
            $this.m_properties.Add("Regions", $regions);
            $this.m_properties.Add("StartTime", [Utility]::DateTimeToString($Message.Message.data.alertContext.properties.impactStartTime));
            $this.m_properties.Add("EndTime", [Utility]::DateTimeToString($Message.Message.data.alertContext.properties.impactMitigationTime));
            $this.m_properties.Add("LastModified", [Utility]::DateTimeToString($Message.Message.data.essentials.firedDateTime));
        }
    }

    [DateTime]GetExpirationTime(
        [BaseMessage]$Message
    )
    {
        $endTimeFromMetadata = $Message.Message.data.alertContext.properties.impactMitigationTime;
        $endTime = $null -eq $endTimeFromMetadata ? $null : $($endTimeFromMetadata -as [DateTime]).AddMonths(2);
        if ($null -eq $endTime)
        {
            return ([BaseEntity]$this).GetExpirationTime();
        } else {
            return $endTime;
        }
    }
}