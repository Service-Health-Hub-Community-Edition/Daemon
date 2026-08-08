using module ..\ConfigurationManager.psm1
using module ..\Utility.psd1
using module ..\Utility.psm1
using module ..\BaseMessage.psm1
using module ..\Logging.psm1
using module ..\SystemAlert.psm1
using module .\NotificationManagerBase.psm1
using module .\RoutingManager.psm1

class LogicAppNotificationManager: NotificationManagerBase
{
	hidden [string]$Endpoint = [string]::Empty;

	LogicAppNotificationManager()
	{

	}

	# legacy support
	LogicAppNotificationManager(
		[string]$Component
	)
	{
		$this.InitializeTemplate($Component);
		$this.Endpoint = [ConfigurationManager]::GetNotificationManagerConfigParameter('LogicAppsNotifications.Endpoint');	
	}

	LogicAppNotificationManager(
		[string]$Component,
        [System.Object]$Configuration,
        [string]$Template
	): base($Component, $Configuration, $Template)
	{
		$this.Endpoint = $($Configuration | Where-Object name -eq "Endpoint").value
	}

	hidden [void]SendMessageInt(
		[Route]$Route
	)
	{
		[TraceLogging]::LogEvent([LoggingLevel]::Information, "LogicAppNotificationManager", "PostMessage", "tm1029", "Entering method LogicAppNotificationManager.SendMessageInt()");
		
		if (![string]::IsNullOrWhiteSpace($this.Endpoint))
		{
			[TraceLogging]::LogEvent([LoggingLevel]::Information, "LogicAppNotificationManager", "PostMessage", "tm1033", "Message endpoint provided, posting message to $($this.Endpoint)");
			$body = [Utility]::FixQuotes($(ConvertTo-Json -Depth 5 $this.MessageTemplate.template -EscapeHandling EscapeHtml))
			try
			{
				Invoke-RestMethod -uri $this.Endpoint -Method Post -body $body -ContentType 'application/json; charset=utf-8'
				[TraceLogging]::LogEvent([LoggingLevel]::Information, "LogicAppNotificationManager", "PostMessage", "tm1034", "Message successfully posted.");
				$this.m_m365shhdb.AddActivityLogRecord(
					[Guid]::Empty,
					[TraceLogging]::CorrelationID,
					'',
					'app-' + [ConfigurationManager]::ClientId + '@'+ [ConfigurationManager]::TenantDomain,
					'NotificationSent',
					'item://' + $this.Entity.m_properties.InternalCommunicationType + '/' + $this.Entity.m_properties.Id,
 					'Notification',
					[Guid]::Empty,
					$this.Entity.m_properties.Id,
					'NotificationManager',
					$Route.ComponentId,
					@{
						Connector = $Route.Connector
						Route = $Route.Name
					},
					$null
				)
			}
			catch
			{
				[TraceLogging]::LogEvent([LoggingLevel]::Error, "LogicAppNotificationManager", "PostMessage", "tm1087", "An exception was caught while posting an adaptive card. Exception: $_");
				[TraceLogging]::LogEvent([LoggingLevel]::Error, "LogicAppNotificationManager", "PostMessage", "tm1087", "Stack trace: $($_.ScriptStackTrace)");
				[TraceLogging]::LogEvent([LoggingLevel]::Error, "LogicAppNotificationManager", "PostMessage", "tm1087", "Data: $body");
				$this.m_m365shhdb.AddActivityLogRecord(
					[Guid]::Empty,
					[TraceLogging]::CorrelationID,
					'',
					'app-' + [ConfigurationManager]::ClientId + '@'+ [ConfigurationManager]::TenantDomain,
					'NotificationFailed',
					'item://' + $this.Entity.m_properties.InternalCommunicationType + '/' + $this.Entity.m_properties.Id,
 					'Notification',
					[Guid]::Empty,
					$this.Entity.m_properties.Id,
					'NotificationManager',
					$Route.ComponentId,
					@{
						Connector = $Route.Connector
						Route = $Route.Name
						Exception = $($null -ne $_.Exception ? $_.Exception.ToString() : $_.ToString())
					},
					$null
				)

				try {
					if ($null -ne $global:systemAlert)
					{
						$alert = [SystemAlert]::new();
						$description = "<p>Couldn't send notification for $($this.Entity.m_properties.Id) - $($this.Entity.m_properties.Title)</p><p>Exception: $($null -ne $_.Exception ? $_.Exception.ToString() : $_.ToString())</p>"
						$alert.Message = [PSCustomObject]@{
							Title = "Error occured while sending notification for communication $($this.Entity.m_properties.Id)"
							Type = "Realtime"
							Description = $description
							Source= "NotificationManager"
							CommunicationID = $this.Entity.m_properties.Id
							CommunicationType = $this.Entity.m_properties.InternalCommunicationType
							Timestamp = [DateTime]::UtcNow
							AdaptiveCardBody = [Utility]::ConvertHTMLToAdaptiveCardBody($description)
						};

						$global:systemAlert.SendMessage($alert);
					}
				}
				catch {
					[TraceLogging]::LogEvent([LoggingLevel]::Error, "LogicAppNotificationManager", "PostMessage", "tm1088", "Couldn't send system alert. Exception: $_");
				}
			}
		}

		[TraceLogging]::LogEvent([LoggingLevel]::Information, "LogicAppNotificationManager", "PostMessage", "tm1099", "Exiting method LogicAppNotificationManager.SendMessageInt()");
	}
}