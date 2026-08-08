using module ..\ConfigurationManager.psm1
using module ..\AuthManagerHelper.psm1
using module ..\AuthManager.psm1
using module ..\Utility.psd1
using module ..\Utility.psm1
using module ..\BaseMessage.psm1
using module ..\Logging.psm1
using module ..\SystemAlert.psm1
using module .\NotificationManagerBase.psm1
using module .\RoutingManager.psm1

class ServiceBusNotificationManager: NotificationManagerBase
{
	hidden [string]$Endpoint = [string]::Empty;
    hidden [AuthManager]$AuthManager = $null;

	ServiceBusNotificationManager()
	{

	}

	# legacy support
	ServiceBusNotificationManager(
		[string]$Component
	)
	{
		$this.InitializeTemplate($Component);
		$this.Endpoint = [ConfigurationManager]::GetNotificationManagerConfigParameter('ServiceBusNotification.Endpoint');
        $this.AuthManager = [AuthManagerHelper]::CreateInstance("https://servicebus.azure.net");
	}

	ServiceBusNotificationManager(
		[string]$Component,
        [System.Object]$Configuration,
        [string]$Template
	): base($Component, $Configuration, $Template)
	{
		$this.Endpoint = $($Configuration | Where-Object name -eq "Endpoint").value
        $this.AuthManager = [AuthManagerHelper]::CreateInstance("https://servicebus.azure.net");
	}

	hidden [void]SendMessageInt(
		[Route]$Route
	)
	{
		[TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceBusNotificationManager", "PostMessage", "sb1029", "Entering method ServiceBusNotificationManager.SendMessageInt()");
		
		$queueName = $Route.GetConnectorConfigurationValue("QueueName");

		if (![string]::IsNullOrWhiteSpace($this.Endpoint))
		{
			[TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceBusNotificationManager", "PostMessage", "sb1033", "Message endpoint provided, posting message to $($this.Endpoint)");
			$body = [Utility]::FixQuotes($this.MessageTemplate.template)
			try
			{
                $headers = @{                                                                                                          
                    Authorization = [string]::Format("{0} {1}", $this.AuthManager.Token.token_type, $this.AuthManager.Token.access_token)
                    "Content-Type" = 'application/json'
                }

				$uri = $this.Endpoint.Trim().TrimEnd('/')
				$uri = $uri + '/' + $queueName + '/messages'

				Invoke-RestMethod -Uri $uri -Method Post -Body $body -Headers $headers -ContentType 'application/json; charset=utf-8'
				[TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceBusNotificationManager", "PostMessage", "sb1034", "Message successfully posted.");
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
				[TraceLogging]::LogEvent([LoggingLevel]::Error, "ServiceBusNotificationManager", "PostMessage", "sb1087", "An exception was caught while posting an adaptive card. Exception: $_");
				[TraceLogging]::LogEvent([LoggingLevel]::Error, "ServiceBusNotificationManager", "PostMessage", "sb1087", "Stack trace: $($_.ScriptStackTrace)");
				[TraceLogging]::LogEvent([LoggingLevel]::Error, "ServiceBusNotificationManager", "PostMessage", "sb1087", "Data: $body");
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
					[TraceLogging]::LogEvent([LoggingLevel]::Error, "ServiceBusNotificationManager", "PostMessage", "sb1088", "Couldn't send system alert. Exception: $_");
				}
			}
		}

		[TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceBusNotificationManager", "PostMessage", "sb1099", "Exiting method ServiceBusNotificationManager.SendMessageInt()");
	}
}