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

class ACSEmailManager: NotificationManagerBase
{
	hidden [string]$Endpoint = [string]::Empty;
    hidden [AuthManager]$AuthManager = $null;

	ACSEmailManager()
	{

	}

	# legacy support
	ACSEmailManager(
		[string]$Component
	)
	{
		$this.InitializeTemplate($Component);
		$this.Endpoint = [ConfigurationManager]::GetNotificationManagerConfigParameter('ACSEmailManager.Endpoint');
        $this.AuthManager = [AuthManagerHelper]::CreateInstance("https://communication.azure.com");
	}

	ACSEmailManager(
		[string]$Component,
        [System.Object]$Configuration,
        [string]$Template
	): base($Component, $Configuration, $Template)
	{
		$this.Endpoint = $($Configuration | Where-Object name -eq "Endpoint").value
        $this.AuthManager = [AuthManagerHelper]::CreateInstance("https://communication.azure.com");
	}

	hidden [void]SendMessageInt(
		[Route]$Route
	)
	{
		[TraceLogging]::LogEvent([LoggingLevel]::Information, "ACSEmailManager", "PostMessage", "acse1029", "Entering method ACSEmailManager.SendMessageInt()");
		
		$senderMail = $($this.Configuration | Where-Object name -eq "Sender").value;
		$recipients = $Route.GetConnectorConfigurationValue("recipients");
		$recipientsList = $recipients -split ";"

		$recipientsArray = @()
		foreach ($recipient in $recipientsList) 
		{
			if (![string]::IsNullOrWhiteSpace($recipient))
			{
				$recipientsArray += @{
					DisplayName = $recipient.Trim()
					Email       = $recipient.Trim()
				}
			}
		}

		$recObj = @{
			To = $recipientsArray
		}

		$this.MessageTemplate.template | Add-Member -MemberType NoteProperty -Name Sender -Value $senderMail
		$this.MessageTemplate.template | Add-Member -MemberType NoteProperty -Name Recipients -Value $recObj

		if (![string]::IsNullOrWhiteSpace($this.Endpoint))
		{
			[TraceLogging]::LogEvent([LoggingLevel]::Information, "ACSEmailManager", "PostMessage", "acse1033", "Message endpoint provided, posting message to $($this.Endpoint)");
			$body = [Utility]::FixQuotes($(ConvertTo-Json -Depth 5 $this.MessageTemplate.template))
			try
			{
                $headers = @{                                                                                                          
                    Authorization				= [string]::Format("{0} {1}", $this.AuthManager.Token.token_type, $this.AuthManager.Token.access_token)
                    "Content-Type"             	= "application/json"
					"repeatability-request-id" 	= [guid]::NewGuid().ToString()
					"repeatability-first-sent" 	= [DateTime]::UtcNow.ToString("r")
                }

				$uri = $this.Endpoint.Trim().TrimEnd('/')
				$uri = $uri + "/emails:send?api-version=2021-10-01-preview"

				Invoke-RestMethod -Uri $uri -Method Post -Body $body -Headers $headers -ContentType 'application/json; charset=utf-8'
				[TraceLogging]::LogEvent([LoggingLevel]::Information, "ACSEmailManager", "PostMessage", "acse1034", "Message successfully posted.");
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
				[TraceLogging]::LogEvent([LoggingLevel]::Error, "ACSEmailManager", "PostMessage", "acse1087", "An exception was caught while posting an adaptive card. Exception: $_");
				[TraceLogging]::LogEvent([LoggingLevel]::Error, "ACSEmailManager", "PostMessage", "acse1087", "Stack trace: $($_.ScriptStackTrace)");
				[TraceLogging]::LogEvent([LoggingLevel]::Error, "ACSEmailManager", "PostMessage", "acse1087", "Data: $body");
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
					[TraceLogging]::LogEvent([LoggingLevel]::Error, "ACSEmailManager", "PostMessage", "acse1088", "Couldn't send system alert. Exception: $_");
				}
				
			}
		}

		[TraceLogging]::LogEvent([LoggingLevel]::Information, "ACSEmailManager", "PostMessage", "acse1099", "Exiting method ACSEmailManager.SendMessageInt()");
	}
}