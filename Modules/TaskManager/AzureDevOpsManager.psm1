using module ..\BaseMessage.psm1
using module ..\ConfigurationManager.psm1
using module ..\Utility.psd1
using module ..\Utility.psm1
using module ..\Logging.psm1
using module ..\MetadataManager.psm1
using module .\TaskManagerBase.psm1
using module ..\KeyVaultManagerHelper.psm1
using module ..\AuthManagerHelper.psm1
using module ..\AuthManager.psm1
using module ..\SystemAlert.psm1

enum AzureDevOpsAuthMode {
    PersonalAccessToken;
    ServicePrincipal;
}

class AzureDevOpsManager:TaskManagerBase
{
    [string]$OrganizationURI = [string]::Empty
    [string]$Project = [string]::Empty
    hidden [string]$PersonalAccessToken = [string]::Empty
    hidden [MetadataManager]$MetadataManager = $null;
    hidden [System.Object]$Config = @{};
    hidden [AzureDevOpsAuthMode]$AuthMode = [AzureDevOpsAuthMode]::ServicePrincipal;
    [AuthManager]$AuthManager = $null;

    AzureDevOpsManager()
    {

    }

    AzureDevOpsManager(
        [string]$Component
    )
    {
        $this.OrganizationURI = [ConfigurationManager]::GetTaskManagerConfigParameter('AzureDevOps.Organization');
        $this.Project = [ConfigurationManager]::GetTaskManagerConfigParameter('AzureDevOps.Project');
        $secretLocation = [ConfigurationManager]::GetTaskManagerConfigParameter('AzureDevOps.SecretLocation');
        $secret = [ConfigurationManager]::GetTaskManagerConfigParameter('AzureDevOps.Secret');

        if (![string]::IsNullOrWhiteSpace($secretLocation)) {
            $this.AuthMode = [AzureDevOpsAuthMode]::PersonalAccessToken;

            switch ($secretLocation)
            {
                'AppSettings' { 
                    $this.PersonalAccessToken = $secret;
                }
                'KeyVault' {
                    $keyVaultManager = [KeyVaultManagerHelper]::CreateInstance();
                    $secretValue = $keyVaultManager.GetSecret($secret);
                    if ($null -ne $secretValue)
                    {
                        $this.PersonalAccessToken = $secretValue.value;
                    } else {
                        $errorMessage = "Secret '$secret' is not found in Key Vault. Please configure the secret and try again";
                        [TraceLogging]::LogEvent([LoggingLevel]::Error, "AzureDevOpsManager", "Initialization", "ado018", $errorMessage);
                        throw $errorMessage;
                    }
                }
                default {
                    $errorMessage = "Unsupported SecretLocation setting: $secretLocation.";
                    [TraceLogging]::LogEvent([LoggingLevel]::Error, "AzureDevOpsManager", "Initialization", "ado01b", $errorMessage);
                    throw $errorMessage;
                }
            }
        } else {
            $authConfigKey = [ConfigurationManager]::GetTaskManagerConfigParameter('AzureDevOps.AuthConfig');
            if ([string]::IsNullOrWhiteSpace($authConfigKey))
            {
                $this.AuthManager = [AuthManagerHelper]::CreateInstance("499b84ac-1321-427f-aa17-267ca6975798");
            } else {
                $authConfigJson = [ConfigurationManager]::GetSecret($authConfigKey);
                $authConfig = ConvertFrom-Json $authConfigJson
                $this.AuthManager = [AuthManager]::new(
                    $authConfig.ClientId,
                    $authConfig.ClientSecret,
                    $authConfig.TenantDomain,
                    "499b84ac-1321-427f-aa17-267ca6975798")
            }
        }

        $this.MetadataManager = [MetadataManager]::new($Component);
    }

    hidden [System.Object] GetAuthHeader()
    {
        $header = $null;
        if ($this.AuthMode -eq [AzureDevOpsAuthMode]::PersonalAccessToken)
        {
            $header = @{
                Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($this.PersonalAccessToken)"))
            }
        } else {
            $header = @{
                Authorization = [string]::Format("{0} {1}", $this.AuthManager.Token.token_type, $this.AuthManager.Token.access_token)
            }
        }

        return $header
    }

    hidden [System.Object] ProcessAzureDevOpsRequest(
        [string]$TicketData,
        [string]$WorkItemType,
        [BaseMessage]$ServiceCommunication
    )
    {
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureDevOpsManager", "Work Item", "ado109", "Entering method AzureDevOpsManager.ProcessAzureDevOpsRequest()");
        $workItem = ConvertFrom-Json $TicketData
        $id = $workItem."System.Id"

        $properties = $workItem | Get-Member | Where-Object MemberType -eq "NoteProperty" | Select-Object -ExpandProperty Name
        $workItemProperties = @()
        foreach ($property in $properties)
        {
            if ($property.ToUpper() -ne "SYSTEM.ID")
            {
                $workItemProperty = @{
                    op = "add"
                    path = "/fields/" + $property
                    from = $null
                    value = $workItem.$property
                }

                $workItemProperties += $workItemProperty
            }
        }

        $AzureDevOpsAuthenicationHeader = $this.GetAuthHeader()

        $workItemJson = $workItemProperties | ConvertTo-Json -Depth 5
        $opType = '';

        try
        {
            if ($null -eq $id)
            {
                $opType = 'Create';

                [TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureDevOpsManager", "Work Item", "ado114", "Creating new work item.");
                Write-Information "Creating new item"
                $uri = [string]::Format('{0}/{1}/_apis/wit/workitems/${2}?api-version=5.1', $this.OrganizationURI , $this.Project, $WorkItemType)
                $apiRes = Invoke-WebRequest -Uri $uri -Method POST -Headers $AzureDevOpsAuthenicationHeader -Body $workItemJson -ContentType "application/json-patch+json;charset=utf-8" -SkipHttpErrorCheck       
            }
            else
            {
                $opType = 'Modify';

                [TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureDevOpsManager", "Work Item", "ado130", "Updating work item $id.");
                $uri = [string]::Format('{0}/{1}/_apis/wit/workitems/{2}?api-version=5.1', $this.OrganizationURI , $this.Project, $id)
                $apiRes = Invoke-WebRequest -Uri $uri -Method PATCH -Headers $AzureDevOpsAuthenicationHeader -Body $workItemJson -ContentType "application/json-patch+json;charset=utf-8" -SkipHttpErrorCheck
            } 
        }
        catch
        {
            $op = ''
            switch ($opType)
            {
                "Create" {
                    $op = "CreateFailed";
                }
                "Update" {
                    $op = "UpdateFailed";
                }
                default {
                    $op = "Unknown";
                }
            }

            $this.m_m365shhdb.AddActivityLogRecord(
					[Guid]::Empty,
					[TraceLogging]::CorrelationID,
					'',
					'app-' + [ConfigurationManager]::ClientId + '@'+ [ConfigurationManager]::TenantDomain,
					$op,
					'item://' + $ServiceCommunication.GetType().FullName.ToUpper() + '/' + $ServiceCommunication.Id,
 					'Task',
					[Guid]::Empty,
					$ServiceCommunication.Id,
					'TaskManager',
					[Guid]::Empty,
					@{
						TaskManager = 'Azure DevOps'
						Instance = $this.OrganizationURI
                        Project = $this.Project
                        TaskType = $WorkItemType
                        Exception = $_
					},
					$null
				)
            
                try {
                    if ($null -ne $global:systemAlert)
					{
                        $alert = [SystemAlert]::new();
                        $description = "<p>Couldn't set task for $($ServiceCommunication.Id)</p><p>Exception: $($null -ne $_.Exception ? $_.Exception.ToString() : $_.ToString())</p>"
                        $alert.Message = [PSCustomObject]@{
                            Title = "Error occured while setting a task for $($ServiceCommunication.Id)"
                            Type = "Realtime"
                            Description = $description
                            Source= "TaskManager"
                            CommunicationID = $ServiceCommunication.Id
                            CommunicationType = $ServiceCommunication.GetType().FullName
                            Timestamp = [DateTime]::UtcNow
                            AdaptiveCardBody = [Utility]::ConvertHTMLToAdaptiveCardBody($description)
                        };

                        $global:systemAlert.SendMessage($alert);
                    }
				}
				catch {
					[TraceLogging]::LogEvent([LoggingLevel]::Error, "AzureDevOpsManager", "Work Item", "ado131", "Couldn't send system alert. Exception: $_");
				}

            throw;
        }

        if ($apiRes.BaseResponse.IsSuccessStatusCode)
        {
            $res = $(ConvertFrom-Json $apiRes.Content)
            $op = ''
            switch ($opType)
            {
                'Create' {
                    $op = 'Created';
                }
                'Modify' {
                    $op = 'Modified';
                }
                default {
                    $op = 'Unknown';
                }
            }

            $this.m_m365shhdb.AddActivityLogRecord(
                [Guid]::Empty,
                [TraceLogging]::CorrelationID,
                '',
                'app-' + [ConfigurationManager]::ClientId + '@'+ [ConfigurationManager]::TenantDomain,
                $op,
                'item://' + $ServiceCommunication.GetType().FullName.ToUpper() + '/' + $ServiceCommunication.Id,
                'Task',
                [Guid]::Empty,
                $ServiceCommunication.Id,
                'TaskManager',
                [Guid]::Empty,
                @{
                    TaskManager = 'Azure DevOps'
                    Instance = $this.OrganizationURI
                    Project = $this.Project
                    TaskType = $WorkItemType
                    TaskId = $res.id
                    TaskUrl = $res._links.html.href
                },
                $null
            )
        } else {
            $op = ''
            switch ($opType)
            {
                "Create" {
                    $op = "CreateFailed";
                }
                "Update" {
                    $op = "UpdateFailed";
                }
                default {
                    $op = "Unknown";
                }
            }

            $this.m_m365shhdb.AddActivityLogRecord(
					[Guid]::Empty,
					[TraceLogging]::CorrelationID,
					'',
					'app-' + [ConfigurationManager]::ClientId + '@'+ [ConfigurationManager]::TenantDomain,
					$op,
					'item://' + $ServiceCommunication.GetType().FullName.ToUpper() + '/' + $ServiceCommunication.Id,
 					'Task',
					[Guid]::Empty,
					$ServiceCommunication.Id,
					'TaskManager',
					[Guid]::Empty,
					@{
						TaskManager = 'Azure DevOps'
						Instance = $this.OrganizationURI
                        Project = $this.Project
                        TaskType = $WorkItemType
                        StatusCode = $apiRes.BaseResponse.StatusCode.Value__
                        Content = $apiRes.Content
					},
					$null
				)

                try {
                    if ($null -ne $global:systemAlert)
					{
                        $alert = [SystemAlert]::new();
                        $description = "<p>Couldn't set task for $($ServiceCommunication.Id)</p><p>HTTP $($apiRes.BaseResponse.StatusCode.Value__): $($apiRes.Content)</p>"
                        $alert.Message = [PSCustomObject]@{
                            Title = "Error occured while setting a task for $($ServiceCommunication.Id)"
                            Type = "Realtime"
                            Description = $description
                            Source= "TaskManager"
                            CommunicationID = $ServiceCommunication.Id
                            CommunicationType = $ServiceCommunication.GetType().FullName
                            Timestamp = [DateTime]::UtcNow
                            AdaptiveCardBody = [Utility]::ConvertHTMLToAdaptiveCardBody($description)
                        };

                        $global:systemAlert.SendMessage($alert);
                    }
				}
				catch {
					[TraceLogging]::LogEvent([LoggingLevel]::Error, "AzureDevOpsManager", "Work Item", "ado132", "Couldn't send system alert. Exception: $_");
				}

                throw "Couldn't perform '$opType' on task for communication $($ServiceCommunication.Id). Status code: $($apiRes.BaseResponse.StatusCode.Value__). Message: $($apiRes.Content)"
        }

        [TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureDevOpsManager", "Work Item", "ado134", "Exiting method AzureDevOpsManager.ProcessAzureDevOpsRequest()");
        return $res
    }

    hidden [void] SetAzureDevOpsTicket(
        [BaseMessage]$ServiceCommunication,
        $WorkItemType,
        [System.Object]$Routing
    )
    {
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureDevOpsManager", "Work Item", "ado150", "Entering method AzureDevOpsManager.SetAzureDevOpsTicket()");
        $newItem = [string]::IsNullOrWhiteSpace($ServiceCommunication.WorkItemId)        
        $workItem = $this.MetadataManager.MapData($ServiceCommunication, $Routing);
        
        $body = ConvertTo-Json -InputObject $workItem -Depth 5
        $res = $this.ProcessAzureDevOpsRequest($body, $WorkItemType, $ServiceCommunication)

        $ServiceCommunication.WorkItemId = $res.id;
        $ServiceCommunication.WorkItemUrl = $res._links.html.href;
        $ServiceCommunication.NewItem = $newItem;
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureDevOpsManager", "Work Item", "ado158", "Exiting method AzureDevOpsManager.SetAzureDevOpsTicket()");
    }
    
    hidden [void] CreateLink(
        [string]$Id,
        [string]$Uri,
        [string]$Comment
    )
    {

        $workItemProperties = @()

        $workItemProperty = @{
            op = "add"
            path = "/relations/-"
            value = @{
                rel = "System.LinkTypes.Related"
                url = $Uri
                attributes = @{
                    comment = $Comment
                }
            }
        }

        $workItemProperties += $workItemProperty;

        $AzureDevOpsAuthenicationHeader = $this.GetAuthHeader()

        $workItemJson = $workItemProperties | ConvertTo-Json -Depth 5

        if ($workItemJson.Trim()[0] -ne "[")
        {
                $workItemJson = "[" + $workItemJson + "]"
        }

        [TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureDevOpsManager", "Work Item", "ado245", "Updating work item $id.");
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureDevOpsManager", "Work Item", "ado246", "$workItemJson");
        $uri = [string]::Format('{0}/{1}/_apis/wit/workitems/{2}?api-version=5.1', $this.OrganizationURI , $this.Project, $id)
        $res = Invoke-RestMethod -Uri $uri -Method PATCH -Headers $AzureDevOpsAuthenicationHeader -Body $workItemJson -ContentType "application/json-patch+json;charset=utf-8"
    }

    hidden [string]UploadFile(
        [string]$FileName,
        [System.Byte[]]$Stream
    )
    {
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureDevOpsManager", "Work Item", "ado408", "Entering method AzureDevOpsManager.UploadFile()");
        $result = [guid]::Empty;

        $AzureDevOpsAuthenicationHeader = $this.GetAuthHeader();

        [TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureDevOpsManager", "Work Item", "ado410", "Uploading file $FileName, length: $($stream.Length).");
        $uri = [string]::Format('{0}/_apis/wit/attachments?fileName={1}&api-version=6.0', $this.OrganizationURI, $FileName)
        $res = Invoke-RestMethod -Uri $uri -Method POST -Headers $AzureDevOpsAuthenicationHeader -Body $Stream -ContentType "application/octet-stream"
        $result = $res.url
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureDevOpsManager", "Work Item", "ado413", "File successfully uploaded. Url: $result");
        
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureDevOpsManager", "Work Item", "ado419", "Exiting method AzureDevOpsManager.UploadFile()");
        return $result
    }

    hidden [void]LinkFile(
        [string]$Id,
        [string]$FileName,
        [string]$FileUrl
    )
    {
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureDevOpsManager", "Work Item", "ado43f", "Entering method AzureDevOpsManager.LinkFile()");

        $AzureDevOpsAuthenicationHeader = $this.GetAuthHeader();

        [TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureDevOpsManager", "Work Item", "ado441", "Attaching file $FileName, from the location $FileUrl to the work item $Id...");

        $workItemProperties = @()

        $workItemProperties += @{
            op = "add"
            path = "/fields/System.History"
            value = "M365 Service Health Sync attached a file $FileName to the work item."
        }

        $workItemProperties += @{
            op = "add"
            path = "/relations/-"
            value = @{
                rel = "AttachedFile"
                url = $FileUrl
                attributes = @{
                    comment = "This file has been attached to the work item by M365 Service Health Sync"
                }
            }
        }

        $workItemJson = $workItemProperties | ConvertTo-Json -Depth 5

        if ($workItemJson.Trim()[0] -ne "[")
        {
                $workItemJson = "[" + $workItemJson + "]"
        }

        $uri = [string]::Format('{0}/{1}/_apis/wit/workitems/{2}?api-version=5.1', $this.OrganizationURI , $this.Project, $id)
        $res = Invoke-RestMethod -Uri $uri -Method PATCH -Headers $AzureDevOpsAuthenicationHeader -Body $workItemJson -ContentType "application/json-patch+json;charset=utf-8"

        [TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureDevOpsManager", "Work Item", "ado449", "File $FileName successfully attached to the work item $Id...");
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureDevOpsManager", "Work Item", "ado44f", "Exiting method AzureDevOpsManager.LinkFile()");
    }

    [void] SetTask(
        [BaseMessage]$ServiceCommunication,
        [System.Object]$Routing
    )
    {
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureDevOpsManager", "Work Item", "ado49a", "Entering method AzureDevOpsManager.SetTask()");
        $commType = $ServiceCommunication.GetType().Name;
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureDevOpsManager", "Work Item", "ado49b", "Determining work item type for communication type: $commType");
        $WorkItemType = [ConfigurationManager]::GetTaskManagerConfigParameter("AzureDevOps.WorkItemType.$commType");
        if ([string]::IsNullOrWhiteSpace($WorkItemType))
        {
            $WorkItemType = "Task"; #default value
            [TraceLogging]::LogEvent([LoggingLevel]::Warning, "AzureDevOpsManager", "Work Item", "ado49d", "Application setting 'AzureDevOps.WorkItemType.$commType' not found. Setting work item type to 'Task'.");      
        } else {
            [TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureDevOpsManager", "Work Item", "ado49f", "Application setting 'AzureDevOps.WorkItemType.$commType' found. Setting work item type to '$WorkItemType'.");
        }
        $this.SetAzureDevOpsTicket($ServiceCommunication, $WorkItemType, $Routing);
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureDevOpsManager", "Work Item", "ado4af", "Exiting method AzureDevOpsManager.SetTask()");
    }

    [void]LinkTasks(
        [BaseMessage]$MessageCenterMessage,
        [BaseMessage]$RoadmapMessage
    )
    {
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureDevOpsManager", "Work Item", "ado4c0", "Entering method AzureDevOpsManager.LinkTasks()");
        if (![string]::IsNullOrWhiteSpace($MessageCenterMessage.WorkItemId) -and 
            ![string]::IsNullOrWhiteSpace($RoadmapMessage.WorkItemId))
        {
            $this.CreateLink($MessageCenterMessage.WorkItemId, $RoadmapMessage.WorkItemUrl, "Roadmap Communication");
            $this.CreateLink($RoadmapMessage.WorkItemId, $MessageCenterMessage.WorkItemUrl, "Message Center Communication");
        }
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureDevOpsManager", "Work Item", "ado4c5", "Exiting method AzureDevOpsManager.LinkTasks()");
    }

    [void]AttachFile(
        [string]$Id,
        [string]$FileName,
        [System.Byte[]]$Stream
    )
    {
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureDevOpsManager", "Work Item", "ado4c7", "Entering method AzureDevOpsManager.AttachFile()");
        $fileUrl = $this.UploadFile($FileName, $Stream);
        $this.LinkFile($Id, $FileName, $fileUrl);
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureDevOpsManager", "Work Item", "ado4ca", "Entering method AzureDevOpsManager.AttachFile()");
    }
}