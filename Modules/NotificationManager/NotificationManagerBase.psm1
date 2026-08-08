using module ..\Utility.psd1
using module ..\Utility.psm1
using module ..\BaseMessage.psm1
using module ..\Logging.psm1
using module ..\EntityMapping\BaseEntity.psm1
using module ..\EntityMapping\ReleaseMessageEntity.psm1
using module ..\EntityMapping\RoadmapEntity.psm1
using module ..\EntityMapping\ServiceIssueEntity.psm1
using module ..\EntityMapping\ServiceUpdateEntity.psm1
using module ..\EntityMapping\AzureServiceHealthAlertEntity.psm1
using module ..\EntityMapping\Office365EndpointsChangeEntity.psm1
using module ..\EntityMapping\AzureUpdateEntity.psm1
using module ..\EntityMapping\AzureAWSSupportTicketEntity.psm1
using module ..\EntityMapping\SystemAlertEntity.psm1
using module ..\EntityMapping\D365PowerPlatformReleaseEntity.psm1
using module ..\EntityMapping\CommonDataConnectorAlertV1Entity.psm1
using module ..\Services\AzureTranslator.psm1
using module ..\M365ServiceHealthHubDB.psm1
using module .\ExpressionHandler.psm1
using module .\RoutingManager.psm1

<#
    EntityProperty = PropertyName : Modifier
    StaticValue = Value
    RoutingProperty = PropertyName : DefaultValue
#>

<#
    new format
    entity://{PropertyName}/{Modifier1}/{Modifier2}?Modifier1_param1=value1&Modifier1_param2=value2&Modifier2_param1...
    static://{staticValueUrlEncoded}/{Modifier}
    route://{PropertyName}?default=defaultValue
    route://root/getConnectorConfigurationValue?getConnectorConfigurationValue_param1=TeamID

    EntityProperty = PropertyName : Modifier
    StaticValue = Value
    RoutingProperty = PropertyName : DefaultValue
#>

class NotificationManagerBase
{
	[string]$Component = [string]::Empty;
    hidden [string]$MessageTemplateSerialized = [string]::Empty;
	[System.Object]$MessageTemplate;
    hidden [M365ServiceHealthHubDB]$m_m365shhdb = [M365ServiceHealthHubDB]::new();
    [System.Object]$Configuration = $null;
    hidden [Expression]$ExpressionHandler = $null;
    hidden [BaseEntity]$Entity = $null;

    NotificationManagerBase()
	{
	}

	NotificationManagerBase(
		[string]$Component
	)
	{
        $this.InitializeTemplate($Component);
	}

    NotificationManagerBase(
		[string]$Component,
        [System.Object]$Configuration,
        [string]$Template
	)
	{
        $this.Configuration = $Configuration;
        $this.MessageTemplateSerialized = $Template;
        $this.Component = $Component;
        $this.DeserializeTemplate();
	}

    [void]InitializeTemplate(
        [string]$Component
    )
    {
        $this.Component = $Component;
		$this.ReloadTemplate();
    }

    # to be fixed
	[void]ReloadTemplate()
	{
		$this.MessageTemplateSerialized = $this.m_m365shhdb.GetSyncConfigEntry($this.Component, "notificationTemplate");
        if ([string]::IsNullOrWhiteSpace($this.MessageTemplateSerialized))
        {
            $warningMessage = "Notification template is not present. Service Communication will be sent in it's raw format.";
            [TraceLogging]::LogEvent([LoggingLevel]::Warning, "NotificationManager", "Template", "nmg10a", $warningMessage);
        }
        $this.DeserializeTemplate();
	}

    [void]DeserializeTemplate()
    {
        # [TraceLogging]::LogEvent([LoggingLevel]::Information, "NotificationManager", "Template", "nmg10a", $this.MessageTemplateSerialized);
        if (![string]::IsNullOrWhiteSpace($this.MessageTemplateSerialized))
        {
            $this.MessageTemplate = ConvertFrom-Json $this.MessageTemplateSerialized;
        } else {
            $this.MessageTemplate = @{
                template = $null
            }
        }
    }


    [void]ExecuteExpressions(
		$RootNode
	)
	{
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "NotificationManager", "Data mapping", "nmg270", "Entering method NotificationManager.MapData().");
        
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "NotificationManager", "Data mapping", "nmg275", "Initialized entity mapper: $($this.Entity.GetType().Name)");

		$properties = $RootNode | Get-Member | Where-Object MemberType -eq NoteProperty
		[TraceLogging]::LogEvent([LoggingLevel]::Verbose, "NotificationManager", "PostMessage", "tm1102", "$($properties.Count) properties enumerated");

		foreach ($property in $properties)
		{
			[TraceLogging]::LogEvent([LoggingLevel]::Verbose, "NotificationManager", "PostMessage", "tm1103", "Processing property $($property.Name)");
			if ($property.Definition.ToUpper().StartsWith("OBJECT[]"))
			{
				[TraceLogging]::LogEvent([LoggingLevel]::Verbose, "NotificationManager", "PostMessage", "tm1110", "Collection found. Processing collection members.");
				foreach ($collectionMemeber in $RootNode.$($property.Name))
				{
                    Write-Host $($collectionMemeber | ConvertTo-Json -Depth 20)
					$this.ExecuteExpressions($collectionMemeber);
                    Write-Host $($collectionMemeber | ConvertTo-Json -Depth 20)
				}
			}
            elseif ($property.Definition.ToUpper().StartsWith("SYSTEM.MANAGEMENT.AUTOMATION.PSCUSTOMOBJECT"))
            {
                [TraceLogging]::LogEvent([LoggingLevel]::Verbose, "NotificationManager", "PostMessage", "tm1119", "Complex object found. Processing members.");
                Write-Host $($RootNode.$($property.Name) | ConvertTo-Json -Depth 20)
                $this.ExecuteExpressions($RootNode.$($property.Name));
                Write-Host $($RootNode.$($property.Name) | ConvertTo-Json -Depth 20)
            }
			else {
				[TraceLogging]::LogEvent([LoggingLevel]::Verbose, "NotificationManager", "PostMessage", "tm1108", "Evaluating expression for member $($property.Name)");
				$RootNode.$($property.Name) = $null -ne $RootNode.$($property.Name) ? $this.ExpressionHandler.GetValue($RootNode.$($property.Name).ToString()) : $null;
			}
		}

		[TraceLogging]::LogEvent([LoggingLevel]::Verbose, "NotificationManager", "PostMessage", "tm1199", "Exiting method ExecuteExpressions().");
	}

	
	[void]SendMessage(
		[BaseMessage]$ServiceCommunication,
		[Route]$Route
	)
	{
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
            "SystemAlert" { $entityMapper = [SystemAlertEntity]::new($ServiceCommunication); }
            "D365PowerPlatformRelease" { $entityMapper = [D365PowerPlatformReleaseEntity]::new($ServiceCommunication); }
            "CommonDataConnectorAlertV1" { $entityMapper = [CommonDataConnectorAlertV1Entity]::new($ServiceCommunication); }
            default { $entityMapper = [BaseEntity]::new($ServiceCommunication); }
        }

        $this.Entity = $entityMapper;
        $this.ExpressionHandler = [Expression]::new($this.Entity, $Route);

        # populate message template
        $this.DeserializeTemplate();

        if (![string]::IsNullOrWhiteSpace($this.MessageTemplateSerialized))
        {
		    [TraceLogging]::LogEvent([LoggingLevel]::Information, "TeamsManager", "PostMessage", "tm1031", "Populating message template");
		    $this.ExecuteExpressions($this.MessageTemplate.template);
        } else {
            [TraceLogging]::LogEvent([LoggingLevel]::Warning, "TeamsManager", "PostMessage", "tm1032", "No message template provided, serializing entity data for a payload.");
		    $this.MessageTemplate.template = $(ConvertTo-Json -InputObject $($ServiceCommunication | Select-Object Id, WorkItemId, WorkItemUrl, Message, LastUpdatedTime, Indexed) -Depth 20);
        }

        $this.SendMessageInt($Route);
	}

    hidden [void]SendMessageInt(
		[Route]$Route
	)
	{
    }
}