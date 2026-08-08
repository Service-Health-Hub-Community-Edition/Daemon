using module ..\BaseMessage.psm1
using module ..\ConfigurationManager.psm1
using module ..\Utility.psd1
using module ..\Utility.psm1
using module ..\Logging.psm1
using module ..\MetadataManager.psm1
using module .\TaskManagerBase.psm1
using module ..\KeyVaultManagerHelper.psm1
using module ..\SystemAlert.psm1

class JiraRequest
{
    [System.Object]$fields = $null;

    JiraRequest(
        [System.Object]$Fields
    )
    {
        $this.fields = $Fields
    }
}

class JiraManager:TaskManagerBase
{
    [string]$InstanceURI = [string]::Empty;
    hidden [string]$Username = [string]::Empty;
    hidden [string]$Password = [string]::Empty;
    hidden [string]$Project = [string]::Enpty;
    hidden [MetadataManager]$MetadataManager = $null;
    hidden [System.Object]$Config = @{};
    hidden [string]$AuthMethod = [string]::Empty;

    JiraManager()
    {

    }

    JiraManager(
        [string]$Component
    )
    {
        $this.InstanceURI = [ConfigurationManager]::GetTaskManagerConfigParameter('Jira.Instance');
        if (![string]::IsNullOrWhiteSpace($this.InstanceURI))
        {
            $this.InstanceURI.Trim().TrimEnd("/");
        }

        $this.Project = [ConfigurationManager]::GetTaskManagerConfigParameter('Jira.Project');

        $this.Username = [ConfigurationManager]::GetTaskManagerConfigParameter('Jira.User');
        $secretLocation = [ConfigurationManager]::GetTaskManagerConfigParameter('Jira.SecretLocation');
        $secret = [ConfigurationManager]::GetTaskManagerConfigParameter('Jira.Secret');
        $this.AuthMethod = [ConfigurationManager]::GetTaskManagerConfigParameter('Jira.AuthMethod');

        switch ($secretLocation)
        {
            'AppSettings' { 
                $this.Password = $secret;
            }
            'KeyVault' {
                $keyVaultManager = [KeyVaultManagerHelper]::CreateInstance();
                $secretValue = $keyVaultManager.GetSecret($secret);
                if ($null -ne $secretValue)
                {
                    $this.Password = $secretValue.value;
                } else {
                    $errorMessage = "Secret '$secret' is not found in Key Vault. Please configure the secret and try again";
                    [TraceLogging]::LogEvent([LoggingLevel]::Error, "JiraManager", "Initialization", "jm018", $errorMessage);
                    throw $errorMessage;
                }
            }
            default {
                $errorMessage = "Unsupported SecretLocation setting: $secretLocation.";
                [TraceLogging]::LogEvent([LoggingLevel]::Error, "JiraManager", "Initialization", "jm01b", $errorMessage);
                throw $errorMessage;        
            }
        }

        $this.MetadataManager = [MetadataManager]::new($Component);
    }

    hidden [System.Object] ProcessJiraRequest(
        [string]$TicketData,
        [string]$IssueType,
        [BaseMessage]$ServiceCommunication
    )
    {
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "JiraManager", "Incident", "jm109", "Entering method JiraManager.ProcessJiraRequest()");
        $incident = ConvertFrom-Json $TicketData
        $id = $incident."key"

        $properties = $incident | Get-Member | Where-Object MemberType -eq "NoteProperty" | Select-Object -ExpandProperty Name
        $fields = @{}

        if ($null -eq $id)
        {
            # we are creating a new item, add project information
            Add-Member -InputObject $fields -NotePropertyName "project" -NotePropertyValue @{ key = $this.Project }
            Add-Member -InputObject $fields -NotePropertyName "issuetype" -NotePropertyValue @{ name = $IssueType } 
        }

        foreach ($property in $properties)
        {
            if ($property.ToUpper() -ne "KEY")
            {
                $mapping = $this.MetadataManager.GetMappingItem($property);
                if ($null -ne $mapping)
                {
                    switch ($mapping.Type)
                    {
                        "option" {
                            Add-Member -InputObject $fields -NotePropertyName $property -NotePropertyValue @{ value = $incident."$property" };
                        }
                        "datetime" {
                            if ([string]::IsNullOrWhiteSpace($incident."$property"))
                            {
                                Add-Member -InputObject $fields -NotePropertyName $property -NotePropertyValue $null
                            } else {
                                $dateTimeValue = $incident."$property";
                                if ($dateTimeValue.GetType().Name -eq "String")
                                {
                                    $dateTimeValue = [datetime]::Parse($dateTimeValue);
                                    $dateTimeValue = [datetime]::SpecifyKind($dateTimeValue, [System.DateTimeKind]::Utc);
                                }
                                $dateTimeStringValue = $dateTimeValue.ToString("yyyy-MM-ddTHH:mm:ss.fff")+$($dateTimeValue.ToString("zzz").Replace(":",""))
                                Add-Member -InputObject $fields -NotePropertyName $property -NotePropertyValue $dateTimeStringValue;
                            }
                        }
                        "labels" {
                            $labels = [System.Collections.Generic.List[System.String]]::new();
                            $labelsArray = @();
                            if ($incident."$property" -is [System.Collections.IEnumerable])
                            {
                                $labelsArray = $incident."$property"
                            } else {
                                $labelsArray = $incident."$property" -split ","
                            }
                            
                            foreach ($label in $labelsArray)
                            {
                                if ($null -eq $label)
                                {
                                    continue;
                                }

                                if ($label -is [System.String])
                                {
                                    $labels.Add([System.Text.RegularExpressions.Regex]::Replace($label.Trim(), "[^a-zA-Z0-9]", ""));
                                } else {
                                    $labels.Add([System.Text.RegularExpressions.Regex]::Replace($label.ToString().Trim(), "[^a-zA-Z0-9]", ""));
                                }
                            }
                            Add-Member -InputObject $fields -NotePropertyName $property -NotePropertyValue $labels
                        }
                        default {
                            Add-Member -InputObject $fields -NotePropertyName $property -NotePropertyValue $incident."$property"
                        }
                    }

                } else {
                    Add-Member -InputObject $fields -NotePropertyName $property -NotePropertyValue $incident."$property"
                }
            }
        }

        $JiraAuthenticationHeader = $null;

        if ($this.AuthMethod -eq "BearerPAT")
        {
            $JiraAuthenticationHeader = @{
                Accept = 'application/json'
                Authorization = 'Bearer ' + $this.Password
                "X-Atlassian-Token" = "nocheck"
            }
        } else {
            $JiraAuthenticationHeader = @{
                Accept = 'application/json'
                Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(("{0}:{1}" -f $this.Username, $this.Password)))
                "X-Atlassian-Token" = "nocheck"
            }
        }

        $incidentJson = '{
    "fields": ' + (ConvertTo-Json -InputObject $fields -Depth 5) + '
}';

        # $incidentJson = $incidentJson | ConvertFrom-Json | ConvertTo-Json -Depth 5

        $notSuccessful = $false
        $maxRetries = 5
        $retryCount = 0
        $rnd = [Random]::new()
        $opType = '';
        $resContent = $null;

        try {
            do {
                $res = $null
                if ($null -eq $id)
                {
                    $opType = 'Create';

                    [TraceLogging]::LogEvent([LoggingLevel]::Information, "JiraManager", "Incident", "jm114", "Creating new incident.");
                    Write-Information "Creating new item"
                    $uri = [string]::Format('{0}/rest/api/2/issue', $this.InstanceURI)
                    $res = Invoke-WebRequest -Uri $uri -Method POST -Headers $JiraAuthenticationHeader -Body $incidentJson -ContentType "application/json;charset=utf-8" -SkipHttpErrorCheck
                    $resContent = $(ConvertFrom-Json $res.Content)

                    if ($res.BaseResponse.IsSuccessStatusCode)
                    {
                        $this.m_m365shhdb.AddActivityLogRecord(
                            [Guid]::Empty,
                            [TraceLogging]::CorrelationID,
                            '',
                            'app-' + [ConfigurationManager]::ClientId + '@'+ [ConfigurationManager]::TenantDomain,
                            'Created',
                            'item://' + $ServiceCommunication.GetType().FullName.ToUpper() + '/' + $ServiceCommunication.Id,
                            'Task',
                            [Guid]::Empty,
                            $ServiceCommunication.Id,
                            'TaskManager',
                            [Guid]::Empty,
                            @{
                                TaskManager = 'Jira'
                                Instance = $this.InstanceURI
                                Project = $this.Project
                                TaskType = $IssueType
                                TaskId = $resContent.key
                                TaskUrl = "$($this.InstanceURI)/browse/$($resContent.key)"
                            },
                            $null
                        )
                    } else 
                    {
                        $this.m_m365shhdb.AddActivityLogRecord(
                            [Guid]::Empty,
                            [TraceLogging]::CorrelationID,
                            '',
                            'app-' + [ConfigurationManager]::ClientId + '@'+ [ConfigurationManager]::TenantDomain,
                            'CreateFailed',
                            'item://' + $ServiceCommunication.GetType().FullName.ToUpper() + '/' + $ServiceCommunication.Id,
                            'Task',
                            [Guid]::Empty,
                            $ServiceCommunication.Id,
                            'TaskManager',
                            [Guid]::Empty,
                            @{
                                TaskManager = 'Jira'
                                Instance = $this.InstanceURI
                                Project = $this.Project
                                TaskType = $IssueType
                                StatusCode = $res.BaseResponse.StatusCode.Value__
                                Content = $res.Content
                            },
                            $null
                        )

                        try {
                            if ($null -ne $global:systemAlert)
					        {
                                $alert = [SystemAlert]::new();
                                $description = "<p>Couldn't set task for $($ServiceCommunication.Id)</p><p>HTTP $($res.BaseResponse.StatusCode.Value__): $($res.Content)</p>"
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
                            [TraceLogging]::LogEvent([LoggingLevel]::Error, "JiraManager", "Incident", "jm116", "Couldn't send system alert. Exception: $_");
                        }

                        if ($res.StatusCode -eq 429 -or $res.StatusCode -eq 503) # part of the retry logic, handled below
                        {
                            throw "Couldn't perform '$opType' on task for communication $($ServiceCommunication.Id). Status code: $($res.BaseResponse.StatusCode.Value__). Message: $($res.Content)"
                        }
                    }
                }
                else
                {
                    $opType = 'Modify';

                    [TraceLogging]::LogEvent([LoggingLevel]::Information, "JiraManager", "Incident", "jm130", "Updating incident $id.");
                    $uri = [string]::Format('{0}/rest/api/2/issue/{1}', $this.InstanceURI, $id)
                    $res = Invoke-WebRequest -Uri $uri -Method PUT -Headers $JiraAuthenticationHeader -Body $incidentJson -ContentType "application/json;charset=utf-8" -SkipHttpErrorCheck
                    $resContent = $(ConvertFrom-Json $res.Content)

                    if ($res.BaseResponse.IsSuccessStatusCode)
                    {
                        $this.m_m365shhdb.AddActivityLogRecord(
                            [Guid]::Empty,
                            [TraceLogging]::CorrelationID,
                            '',
                            'app-' + [ConfigurationManager]::ClientId + '@'+ [ConfigurationManager]::TenantDomain,
                            'Modified',
                            'item://' + $ServiceCommunication.GetType().FullName.ToUpper() + '/' + $ServiceCommunication.Id,
                            'Task',
                            [Guid]::Empty,
                            $ServiceCommunication.Id,
                            'TaskManager',
                            [Guid]::Empty,
                            @{
                                TaskManager = 'Jira'
                                Instance = $this.InstanceURI
                                Project = $this.Project
                                TaskType = $IssueType
                                TaskId = $resContent.key
                                TaskUrl = "$($this.InstanceURI)/browse/$($resContent.key)"
                            },
                            $null
                        )
                    } else 
                    {
                        $this.m_m365shhdb.AddActivityLogRecord(
                            [Guid]::Empty,
                            [TraceLogging]::CorrelationID,
                            '',
                            'app-' + [ConfigurationManager]::ClientId + '@'+ [ConfigurationManager]::TenantDomain,
                            'UpdateFailed',
                            'item://' + $ServiceCommunication.GetType().FullName.ToUpper() + '/' + $ServiceCommunication.Id,
                            'Task',
                            [Guid]::Empty,
                            $ServiceCommunication.Id,
                            'TaskManager',
                            [Guid]::Empty,
                            @{
                                TaskManager = 'Jira'
                                Instance = $this.InstanceURI
                                Project = $this.Project
                                TaskType = $IssueType
                                StatusCode = $res.BaseResponse.StatusCode.Value__
                                Content = $res.Content
                            },
                            $null
                        )

                        try {
                            if ($null -ne $global:systemAlert)
					        {
                                $alert = [SystemAlert]::new();
                                $description = "<p>Couldn't set task for $($ServiceCommunication.Id)</p><p>HTTP $($res.BaseResponse.StatusCode.Value__): $($res.Content)</p>"
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
                            [TraceLogging]::LogEvent([LoggingLevel]::Error, "JiraManager", "Incident", "jm132", "Couldn't send system alert. Exception: $_");
                        }

                        if ($res.StatusCode -eq 429 -or $res.StatusCode -eq 503) # part of the retry logic, handled below
                        {
                            throw "Couldn't perform '$opType' on task for communication $($ServiceCommunication.Id). Status code: $($res.BaseResponse.StatusCode.Value__). Message: $($res.Content)"
                        }
                    }
                }

                if ($res.StatusCode -eq 429 -or $res.StatusCode -eq 503)
                {
                    if ($null -ne $res.Headers.'Retry-After')
                    {
                        Sleep $($res.Headers.'Retry-After' * $rnd.Next(110,130)/100)
                    } else {
                        Sleep $(10 * $rnd.Next(110,130)/100)
                    }

                    $notSuccessful = $true
                    $retryCount ++
                }

            } while ($notSuccessful -or $retryCount -eq $maxRetries)
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
                            TaskManager = 'Jira'
                            Instance = $this.InstanceURI
                            Project = $this.Project
                            TaskType = $IssueType
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
                [TraceLogging]::LogEvent([LoggingLevel]::Error, "JiraManager", "Incident", "jm133", "Couldn't send system alert. Exception: $_");
            }

            throw;
        }

        [TraceLogging]::LogEvent([LoggingLevel]::Information, "JiraManager", "Incident", "jm134", "Exiting method JiraManager.ProcessJiraRequest()");
 
        if ($res.BaseResponse.IsSuccessStatusCode)
        {
            return $resContent
        }
        else {
            throw "Couldn't perform '$opType' on task for communication $($ServiceCommunication.Id). Status code: $($res.BaseResponse.StatusCode.Value__). Message: $($res.Content)"
        }
    }

    [void] SetTask(
        [BaseMessage]$ServiceCommunication,
        [System.Object]$Routing
    )
    {
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "JiraManager", "Incident", "jm150", "Entering method JiraManager.SetJiraTicket()");
        $newItem = [string]::IsNullOrWhiteSpace($ServiceCommunication.WorkItemId);
        $commType = $ServiceCommunication.GetType().Name;
        $IssueType = [ConfigurationManager]::GetTaskManagerConfigParameter("Jira.IssueType.$commType");   
        $incident = $this.MetadataManager.MapData($ServiceCommunication, $Routing);
        
        $body = ConvertTo-Json -InputObject $incident -Depth 5
        $res = $this.ProcessJiraRequest($body, $IssueType, $ServiceCommunication)

        $ServiceCommunication.WorkItemId = $res.key;
        $ServiceCommunication.WorkItemUrl = "$($this.InstanceURI)/browse/$($res.key)";
        $ServiceCommunication.NewItem = $newItem;
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "JiraManager", "Incident", "jm158", "Exiting method JiraManager.SetJiraTicket()");
    }

    [void]LinkTasks(
        [BaseMessage]$MessageCenterMessage,
        [BaseMessage]$RoadmapMessage
    )
    {
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "JiraManager", "Incident", "jm4c0", "Entering method JiraManager.LinkTasks()");

        if (![string]::IsNullOrWhiteSpace($RoadmapMessage.WorkItemId) -and ![string]::IsNullOrWhiteSpace($MessageCenterMessage.WorkItemId))
        {      
            if ($this.AuthMethod -eq "BearerPAT")
            {
                $JiraAuthenticationHeader = @{
                    Accept = 'application/json'
                    Authorization = 'Bearer ' + $this.Password
                    "X-Atlassian-Token" = "nocheck"
                }
            } else {
                $JiraAuthenticationHeader = @{
                    Accept = 'application/json'
                    Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(("{0}:{1}" -f $this.Username, $this.Password)))
                    "X-Atlassian-Token" = "nocheck"
                }
            }     

            $linkData = @{
                type = @{
                    name = "Duplicate"
                }
                inwardIssue = @{
                    key = $RoadmapMessage.WorkItemId
                }
                outwardIssue = @{
                    key = $MessageCenterMessage.WorkItemId
                }
                comment = @{
                    body = "Linked related item"
                }
            }

            $incidentJson = $linkData | ConvertTo-Json -Depth 5

            [TraceLogging]::LogEvent([LoggingLevel]::Information, "JiraManager", "Incident", "jm130", "Updating incident $($RoadmapMessage.WorkItemId). Setting $($MessageCenterMessage.WorkItemId) as a parent incident.");
            $uri = [string]::Format('{0}/rest/api/2/issueLink', $this.InstanceURI)
            $res = Invoke-RestMethod -Uri $uri -Method POST -Headers $JiraAuthenticationHeader -Body $incidentJson -ContentType "application/json;charset=utf-8"
        }
        else {
            [TraceLogging]::LogEvent([LoggingLevel]::Warning, "JiraManager", "Incident", "jm4c4", "Could not create link. Reason: Message center communication or roadmap communication do not have task created.");
            [TraceLogging]::LogEvent([LoggingLevel]::Information, "JiraManager", "Incident", "jm4c5", "Roadmap task id: $($RoadmapMessage.WorkItemId). Message Center task id: $($MessageCenterMessage.WorkItemId)");
        }
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "JiraManager", "Incident", "jm4cf", "Exiting method JiraManager.LinkTasks()");
    }

    [void]AttachFile(
        [string]$Id,
        [string]$FileName,
        [System.Byte[]]$Stream
    )
    {
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "JiraManager", "Incident", "jm4c7", "Entering method JiraManager.AttachFile()");
        
        if ($this.AuthMethod -eq "BearerPAT")
        {
            $JiraAuthenticationHeader = @{
                Authorization = 'Bearer ' + $this.Password
                Cookie = 'ApplicationGatewayAffinity=b802c7b345680ee83531eab2eefb3136; ApplicationGatewayAffinityCORS=b802c7b345680ee83531eab2eefb3136; JSESSIONID=7793BA35752C5E75473117BE601838FB; atlassian.xsrf.token=APLM-80KC-KM4C-X456_6a22438cf09b651ffc8307d95d0b90d92202aa95_lin'
                "X-Atlassian-Token" = "nocheck"
            }
        } else {
            $JiraAuthenticationHeader = @{
                Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(("{0}:{1}" -f $this.Username, $this.Password)))
                "X-Atlassian-Token" = "nocheck"
            }
        }

        $uri = [string]::Format("{0}/rest/api/3/issue/{1}/attachments", $this.InstanceURI, $Id);

        $multipartContent = [System.Net.Http.MultipartFormDataContent]::new()
        $byteArrayContent = [System.Net.Http.ByteArrayContent]::new($Stream);
        $byteArrayContent.Headers.ContentDisposition = [System.Net.Http.Headers.ContentDispositionHeaderValue]::new("form-data");
        $byteArrayContent.Headers.ContentDisposition.Name = "file";
        $byteArrayContent.Headers.ContentDisposition.FileName = $FileName;
        $multipartContent.Add($byteArrayContent);
        $boundary = [System.Guid]::NewGuid().ToString();

        [TraceLogging]::LogEvent([LoggingLevel]::Information, "JiraManager", "Incident", "jm4c8", "Attaching file $FileName, length: $($stream.Length).");
        try {
            $res = Invoke-RestMethod -Uri $uri -Method Post -Body $multipartContent -Headers $JiraAuthenticationHeader -ContentType "multipart/form-data; boundary=`"$boundary`""

            if ($null -ne $res)
            {
                [TraceLogging]::LogEvent([LoggingLevel]::Information, "JiraManager", "Incident", "jm4ca", "File successfully uploaded. Url: $($res.result.download_link)");
            }
        }
        catch {
            [TraceLogging]::LogEvent([LoggingLevel]::Error, "JiraManager", "Incident", "jm4cb", "File is not uploaded. Error: $($_.ErrorDetails.Message). Exception: $($_.Exception). Stack trace: $($_.ScriptStackTrace)");
        }
        
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "JiraManager", "Incident", "jm4cf", "Exiting method JiraManager.AttachFile()");
    }
}