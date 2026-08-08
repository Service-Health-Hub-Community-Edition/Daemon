using module .\Logging.psm1
using module .\Utility.psd1
using module .\Utility.psm1
using module .\Services\AzureTranslator.psm1
using module .\BaseMessage.psm1
using module .\EntityMapping\BaseEntity.psm1
using module .\EntityMapping\ReleaseMessageEntity.psm1
using module .\EntityMapping\RoadmapEntity.psm1
using module .\EntityMapping\ServiceIssueEntity.psm1
using module .\EntityMapping\ServiceUpdateEntity.psm1
using module .\EntityMapping\AzureServiceHealthAlertEntity.psm1
using module .\EntityMapping\Office365EndpointsChangeEntity.psm1
using module .\EntityMapping\AzureUpdateEntity.psm1
using module .\EntityMapping\AzureAWSSupportTicketEntity.psm1
using module .\EntityMapping\D365PowerPlatformReleaseEntity.psm1
using module .\EntityMapping\CommonDataConnectorAlertV1Entity.psm1
using module .\M365ServiceHealthHubDB.psm1

class MetadataManager
{
    hidden [System.Object[]]$MetadataMapping = $null
    hidden [M365ServiceHealthHubDB]$m_m365shhdb = [M365ServiceHealthHubDB]::new();

    MetadataManager()
    {

    }

    MetadataManager(
        [string]$Component
    )
    {
        if (![string]::IsNullOrWhiteSpace($Component))
        {
            $MetadataMappingSerialized = $this.m_m365shhdb.GetSyncConfigEntry($Component, "metadataMapping");
            if ([string]::IsNullOrWhiteSpace($MetadataMappingSerialized))
            {
                $errorMessage = "Mapping configuration for the component $Component is not present. Please specify a mapping configuration in the Microsoft Service Health Hub Admin Center and try again.";
                [TraceLogging]::LogEvent([LoggingLevel]::Error, "NotificationManager", "Template", "mmd10a", $errorMessage);
                throw $errorMessage;
            } else {
                $this.MetadataMapping = ($MetadataMappingSerialized | ConvertFrom-Json)
            }
        } else {
            $this.MetadataMapping = @()
        }
    }

    [System.Object]MapData(
        [BaseMessage]$ServiceCommunication
    )
    {
        return $this.MapData($ServiceCommunication, $null)
    }

    [bool]PropertyExists(
        [System.Object]$Object,
        [string]$PropertyName
    )
    {
        return -not $($null -eq $($Object | Get-Member | Where-Object Name -eq $PropertyName))
    }

    hidden [string] Translate(
        [AzureTranslator]$Translator,
        [System.Object]$Mapping,
        [System.Object]$RoutingData,
        [string]$Content
    )
    {
        $result = $Content;

        if ($Mapping.Translatable -eq $true -and ![string]::IsNullOrWhiteSpace($RoutingData.Language))
        {
            $Language = $RoutingData.Language.Trim();

            [TraceLogging]::LogEvent([LoggingLevel]::Information, "MetadataManager", "Data mapping", "mmd301", "Translating to language $Language.");

            try {
                $translation = $Translator.Translate($Content, @($Language));
                $result = $translation[$Language];
            }
            catch {
                [TraceLogging]::LogEvent([LoggingLevel]::Error, "MetadataManager", "Data mapping", "mmd301a", "Exception caught during translation to language '$Language'. Using original content. Exception: $($_.Exception). Error details: $($_.ErrorDetails). Stack trace: $($_.ScriptStackTrace)");
            }
        }

        return $result;
    }

    [System.Object]GetMappingItem(
        [string]$Destination
    )
    {
        $result = $this.MetadataMapping.Mapping | Where-Object Destination -eq $Destination | Select-Object -First 1
        return $result;
    }

    [System.Object]MapData(
        [BaseMessage]$ServiceCommunication,
        [System.Object]$RoutingData
    )
    {
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "MetadataManager", "Data mapping", "mmd270", "Entering method MetadataManager.MapData().");
        $newItem = [string]::IsNullOrWhiteSpace($ServiceCommunication.WorkItemId);
        $workItem = New-Object -TypeName PSObject

        # initialize entity mapper
        $entityMapper = $null;
        $dataType = $ServiceCommunication.GetType().Name;
        switch ($dataType)
        {
            "ReleaseMessage" { $entityMapper = [ReleaseMessageEntity]::new($ServiceCommunication); }
            "RoadmapCommunication" { $entityMapper = [RoadmapEntity]::new($ServiceCommunication); }
            "ServiceUpdateMessage" { $entityMapper = [ServiceUpdateEntity]::new($ServiceCommunication); }
            "ServiceHealthIssue" { $entityMapper = [ServiceIssueEntity]::new($ServiceCommunication); }
            "AzureServiceHealthAlert" { $entityMapper = [AzureServiceHealthAlertEntity]::new($ServiceCommunication); }
            "Office365EndpointsChange" { $entityMapper = [Office365EndpointsChangeEntity]::new($ServiceCommunication); }
            "AzureUpdate" { $entityMapper = [AzureUpdateEntity]::new($ServiceCommunication); }
            "AzureAWSSupportTicket" { $entityMapper = [AzureAWSSupportTicketEntity]::new($ServiceCommunication); }
            "D365PowerPlatformRelease" { $entityMapper = [D365PowerPlatformReleaseEntity]::new($ServiceCommunication); }
            "CommonDataConnectorAlertV1" { $entityMapper = [CommonDataConnectorAlertV1Entity]::new($ServiceCommunication); }
            default { $entityMapper = [BaseEntity]::new($ServiceCommunication); }
        }

        $translator = [AzureTranslator]::new();

        [TraceLogging]::LogEvent([LoggingLevel]::Information, "MetadataManager", "Data mapping", "mmd275", "Data type: $dataType. Initialized entity mapper: $($entityMapper.GetType().Name)");

        [TraceLogging]::LogEvent([LoggingLevel]::Information, "MetadataManager", "Data mapping", "mmd287", "Found $($this.MetadataMapping.Mapping.Count) mapping entries. Processing...");
        
        # process metadata mapping
        foreach ($mapping in $this.MetadataMapping.Mapping)
        {
            [TraceLogging]::LogEvent([LoggingLevel]::Information, "MetadataManager", "Data mapping", "mmd294", "Processing $($mapping.Name)...");
            if (($newItem -and $([Utility]::ParseBooleanValue($mapping.IncludeForCreate, $false))) -or (!$newItem -and $([Utility]::ParseBooleanValue($mapping.IncludeForUpdate, $false))))
            {
                $value = $null;
                if ($this.PropertyExists($mapping, "EntityProperty")){
                    if ($mapping.ConvertToPlainText -eq $true)
                    {
                        $value = $entityMapper.ConvertToPlainText($mapping.EntityProperty);
                    } else {
                        $value = $entityMapper.GetProperty($mapping.EntityProperty);
                    }

                    if ($this.PropertyExists($mapping, "ValueMapping"))
                    {
                        [TraceLogging]::LogEvent([LoggingLevel]::Information, "MetadataManager", "Data mapping", "mmd29a", "Entering ValueMapping, Property: $($mapping.Destination). Entity value: $value");
                        $valueMap = $mapping.ValueMapping | Where-Object sourceValue -eq $value
                        if ($null -ne $valueMap)
                        {
                            [TraceLogging]::LogEvent([LoggingLevel]::Information, "MetadataManager", "Data mapping", "mmd29b", "ValueMapping match found.");
                            $valueMap = $valueMap | Select-Object -First 1;
                            $value = $valueMap.destinationValue;
                            [TraceLogging]::LogEvent([LoggingLevel]::Information, "MetadataManager", "Data mapping", "mmd29d", "Exiting ValueMapping, Property: $($mapping.Destination). New value: $value");
                        }
                    }

                    $value = $this.Translate($translator, $mapping, $RoutingData, $value);
                    
                    [TraceLogging]::LogEvent([LoggingLevel]::Information, "MetadataManager", "Data mapping", "mmd302", "Property: $($mapping.Destination). Entity value: $value");
                }
                elseif ($this.PropertyExists($mapping, "StaticValue")){
                    $value = $mapping.StaticValue;
                    $value = $this.Translate($translator, $mapping, $RoutingData, $value);
                    [TraceLogging]::LogEvent([LoggingLevel]::Information, "MetadataManager", "Data mapping", "mmd304", "Property: $($mapping.Destination). Static value: $value");
                } elseif ($this.PropertyExists($mapping, "RoutingProperty") -and ($null -ne $RoutingData)) {
                    $routingInfo = $RoutingData | Select-Object -First 1
                    $value = $routingInfo.$($mapping.RoutingProperty);
                    if ([string]::IsNullOrWhiteSpace($value))
                    {
                        $value = $routingInfo.$($mapping.RoutingDefault);
                    }
                    [TraceLogging]::LogEvent([LoggingLevel]::Information, "MetadataManager", "Data mapping", "mmd306", "Property: $($mapping.Destination). Routing value: $value");
                } elseif ($this.PropertyExists($mapping, "Expression")) {
                    $value = $(Invoke-Expression $mapping.Expression);
                    $value = $this.Translate($translator, $mapping, $RoutingData, $value);
                    [TraceLogging]::LogEvent([LoggingLevel]::Information, "MetadataManager", "Data mapping", "mmd308", "Property: $($mapping.Destination). PowerShell Expression result: $value");
                }
                else {
                    $value = $null;
                }
                Add-Member -InputObject $workItem -NotePropertyName $mapping.Destination -NotePropertyValue $value
            }
        }

        [TraceLogging]::LogEvent([LoggingLevel]::Information, "MetadataManager", "Data mapping", "mmd394", "Exiting method MetadataManager.MapData().");
        return $workItem
    }
}