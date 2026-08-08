using module ..\Utility.psd1
using module ..\Utility.psm1
using module ..\BaseMessage.psm1
using module ..\Logging.psm1
using module ..\SystemAlert.psm1
using module .\NotificationManagerBase.psm1
using module .\RoutingManager.psm1
using module ..\ConfigurationManager.psm1
using module ..\AuthManager.psm1
using module ..\AuthManagerHelper.psm1

class TeamsNativeManager: NotificationManagerBase
{
	TeamsNativeManager()
	{

	}

	TeamsNativeManager(
		[string]$Component
	): base($Component)
	{
		
	}

	TeamsNativeManager(
		[string]$Component,
        [System.Object]$Configuration,
        [string]$Template
	): base($Component, $Configuration, $Template)
	{
		
	}

	hidden [void]SendMessageInt(
		[Route]$Route
	)
	{
		[TraceLogging]::LogEvent([LoggingLevel]::Information, "TeamsNativeManager", "PostMessage", "tnm1029", "Entering method TeamsNativeManager.SendMessageInt()");
		
		$webhookUri = $Route.GetConnectorConfigurationValue("TeamsWorkflowUri");

		$headers = $null;
		$uriObj = [uri]::new($webhookUri);
		$query = $uriObj.Query.TrimStart("?");
		$sasUsed = $false;

		try {
			$queryParams = ConvertFrom-StringData $($query.Split("&") -join "`r`n")
			$sasUsed = $queryParams.ContainsKey("sig") -and $queryParams.ContainsKey("sv")	
		}
		catch {
			[TraceLogging]::LogEvent([LoggingLevel]::Warning, "TeamsNativeManager", "PostMessage", "tnm1030", "There was an error while parsing the query string. Exception: $_");
			[TraceLogging]::LogEvent([LoggingLevel]::Warning, "TeamsNativeManager", "PostMessage", "tnm1031", "Assuming the SAS token is not used.");

			$sasUsed = $false;
		}

		if (!$sasUsed){
			[TraceLogging]::LogEvent([LoggingLevel]::Warning, "TeamsNativeManager", "PostMessage", "tnm1032", "SAS token not used. Assuming the authentication is required. Retrieving auth token.");
			
			$authConfigKey = [ConfigurationManager]::PowerAutomateAuthConfig;
            $authMgr = $null;        
			if ([string]::IsNullOrWhiteSpace($authConfigKey))
			{
				$authMgr = [AuthManagerHelper]::CreateInstance("https://service.flow.microsoft.com/");
			} else {
				$authConfigJson = [ConfigurationManager]::GetSecret($authConfigKey);
				$authConfig = ConvertFrom-Json $authConfigJson
				$authMgr = [AuthManager]::new(
					$authConfig.ClientId,
					$authConfig.ClientSecret,
					$authConfig.TenantDomain,
					"https://service.flow.microsoft.com/")
			}

			$token = $authMgr.GetAuthToken();
			
			$headers = @{
				"Authorization" = [string]::Format("{0} {1}", $token.token_type, $token.access_token)
			}
		}

		if (![string]::IsNullOrWhiteSpace($webhookUri))
		{
			[TraceLogging]::LogEvent([LoggingLevel]::Information, "TeamsNativeManager", "PostMessage", "tnm1033", "Message endpoint provided, posting message to $webhookUri");
			$body = [Utility]::FixQuotes($(ConvertTo-Json -Depth 20 $this.MessageTemplate.template -EscapeHandling EscapeHtml))
			try
			{
				if ($null -ne $headers)
				{
					Invoke-RestMethod -Uri $webhookUri -Method Post -body $body -ContentType 'application/json; charset=utf-8' -Headers $headers
				} else {
					Invoke-RestMethod -Uri $webhookUri -Method Post -body $body -ContentType 'application/json; charset=utf-8'
				}
				
				[TraceLogging]::LogEvent([LoggingLevel]::Information, "TeamsNativeManager", "PostMessage", "tnm1034", "Message successfully posted.");
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
				[TraceLogging]::LogEvent([LoggingLevel]::Error, "TeamsNativeManager", "PostMessage", "tnm1087", "An exception was caught while posting an adaptive card. Exception: $_");
				[TraceLogging]::LogEvent([LoggingLevel]::Error, "TeamsNativeManager", "PostMessage", "tnm1087", "Stack trace: $($_.ScriptStackTrace)");
				[TraceLogging]::LogEvent([LoggingLevel]::Error, "TeamsNativeManager", "PostMessage", "tnm1087", "Data: $body");
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
					[TraceLogging]::LogEvent([LoggingLevel]::Error, "TeamsNativeManager", "PostMessage", "tnm1088", "Couldn't send system alert. Exception: $_");
				}
			}
		}

		[TraceLogging]::LogEvent([LoggingLevel]::Information, "TeamsNativeManager", "PostMessage", "tnm1099", "Exiting method TeamsNativeManager.SendMessageInt()");
	}
}