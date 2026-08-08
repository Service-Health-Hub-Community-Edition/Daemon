using module ..\BaseMessage.psm1
using module ..\ConfigurationManager.psm1
using module ..\Utility.psd1
using module ..\Utility.psm1
using module ..\Logging.psm1
using module ..\MetadataManager.psm1
using module .\TaskManagerBase.psm1
using module ..\KeyVaultManagerHelper.psm1

class ServiceNowManager:TaskManagerBase {
    [string]$InstanceURI = [string]::Empty
    hidden [string]$Username = [string]::Empty
    hidden [string]$Password = [string]::Empty
    hidden [System.Object]$AuthConfig = $null    
    hidden [MetadataManager]$MetadataManager = $null;
    hidden [System.Object]$Config = @{};

    ServiceNowManager() {

    }

    ServiceNowManager(
        [string]$Component
    ) {
        $this.InstanceURI = [ConfigurationManager]::GetTaskManagerConfigParameter('ServiceNow.Instance');
        if (![string]::IsNullOrWhiteSpace($this.InstanceURI)) {
            $this.InstanceURI.Trim().TrimEnd("/");
        }

        $secretLocation = [ConfigurationManager]::GetTaskManagerConfigParameter('ServiceNow.SecretLocation');

        switch ($secretLocation) {
            'AppSettings' { 
                $this.Username = [ConfigurationManager]::GetTaskManagerConfigParameter('ServiceNow.User');    
                $this.Password = [ConfigurationManager]::GetTaskManagerConfigParameter('ServiceNow.Secret'); ;
            }
            'KeyVault' {
                $keyVaultManager = [KeyVaultManagerHelper]::CreateInstance();
                $this.AuthConfig = ConvertFrom-Json $keyVaultManager.GetSecret("ServiceNow-AuthConfig").value;
                if ($null -eq $this.authConfig) {
                    $errorMessage = "Secret 'ServiceNow-AuthConfig' is not found in Key Vault. Please configure the secret and try again";
                    [TraceLogging]::LogEvent([LoggingLevel]::Error, "ServiceNowManager", "Initialization", "snm018", $errorMessage);
                    throw $errorMessage;
                }
            }
            default {
                $errorMessage = "Unsupported SecretLocation setting: $secretLocation.";
                [TraceLogging]::LogEvent([LoggingLevel]::Error, "ServiceNowManager", "Initialization", "snm01b", $errorMessage);
                throw $errorMessage;        
            }
        }

        $this.MetadataManager = [MetadataManager]::new($Component);
    }

    hidden [System.Object] GetAuthHeader() {
        if ($null -eq $this.AuthConfig) {
            return @{
                Accept        = 'application/json'
                Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $this.Username, $this.Password)))
            }
        }
        else {
            $keyVaultManager = [KeyVaultManagerHelper]::CreateInstance();
            $certObject = $keyVaultManager.GetSecret($this.AuthConfig.certName)
            $pkb = [Convert]::FromBase64String($certObject.value)
            $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($pkb) 
            $authProviderUri = $this.AuthConfig.authEndpointUri

            #1. NetIQ: Get Cookies
            $urlForLoginCert = "$($authProviderUri)/nidp//app"
            $contentType = "application/x-www-form-urlencoded"
            $session = $null
            $getCookieResponse = Invoke-WebRequest -Certificate $cert -Uri $urlForLoginCert -Method Get -SessionVariable "session" -ContentType $contentType

            #2. NetIQ: Exchange the Personal Code for the Authorization Code
            $urlForExchangeCode = "$($authProviderUri)/nidp/oauth/nam/authz?response_type=code&client_id=$($this.AuthConfig.clientId)&scope=profile1"
            $exchangeCodeResponse = Invoke-WebRequest -Uri $urlForExchangeCode -MaximumRedirection 0 -SkipHttpErrorCheck -WebSession $session -ErrorAction 'silentlycontinue'
            $code = $exchangeCodeResponse.Headers.Location.Split("=")[1].Split("&")[0]

            #3. NetIQ: Token
            $body = @{code     = "$code"; 
                grant_type     = "authorization_code"; 
                client_id      = $this.AuthConfig.clientId; 
                client_secret  = $this.AuthConfig.clientSecret; 
                resourceServer = "Unencrypted" 
            } 
            $Content = Invoke-WebRequest -Uri "$($authProviderUri)/nidp/oauth/nam/token" -Method Post -Body $body -WebSession $Session 
            $token = ($Content.Content | ConvertFrom-Json).access_token

            $headers = @{
                Authorization = "Bearer $token"
                "x-api-key" = $this.AuthConfig.clientId
                Accept = "application/json"
            }

            return $headers
        }
    }

    hidden [string] GetTaskUrl(
        [string]$Id
    )
    {
        $baseUrl = $this.InstanceURI;
        if ($null -ne $this.AuthConfig -and ![string]::IsNullOrWhiteSpace($this.AuthConfig.BaseURI))
        {
            $baseUrl = $this.AuthConfig.BaseURI
        }

        return "$baseUrl/nav_to.do?uri=%2Fincident.do%3Fsys_id%3D$Id"
    }

    hidden [System.Object] GetEnvironment(
        [string]$CloudEnvironment
    )
    {
        if ([string]::IsNullOrWhiteSpace($CloudEnvironment))
        {
            return $this.AuthConfig.defaultCallerId
        }

        $url = [string]::Format("{0}?table=u_cmdb_ci_cloud_environment&queryString=u_alt_ci_id={1}", $this.InstanceURI, $CloudEnvironment);
        $headers = $this.GetAuthHeader();
        $response = Invoke-WebRequest -ContentType "application/json" -Uri $url -Method "GET" -Headers $headers -UseBasicParsing -SkipHttpErrorCheck

        $res = $null;

        if ($response.BaseResponse.IsSuccessStatusCode) {
            $responseObject = $response.Content | ConvertFrom-JSON -Depth 99
            $ce = $responseObject.result.answer.items | Where-Object className -eq u_cmdb_ci_cloud_environment | Select-Object -First 1
            $res = $ce
        } else {
            $res = $null
        }
        return $res
    }

    hidden [string] GetCallerId(
        [System.Object]$CloudEnvironment
    )
    {
        $res = $null
        if ($null -ne $CloudEnvironment -and $null -ne $CloudEnvironment.value.owned_by)
        {
            $res = $CloudEnvironment.value.owned_by
        } else
        {
            $res = $this.AuthConfig.defaultCallerId
        }

        return $res
    }

    hidden [void] CloseIncident(
        [BaseMessage]$ServiceCommunication,
        [string]$Id
    )
    {
        $ServiceNowAuthenticationHeader = $this.GetAuthHeader()
        $uri = $this.InstanceURI
        $closeIncidentPayload = @{
            items = @(
                @{
                    className = "incident"
                    values = @{
                        number = $Id
                        state = "6"
                        close_notes = $this.AuthConfig.closeNotes
                        close_code = "Solved (Permanently)"
                        resolved_by = $this.AuthConfig.resolvedBy
                    }
                }
            )
        }

        $incidentJson = ConvertTo-Json $closeIncidentPayload -Depth 15
        $apiRes = Invoke-WebRequest -Uri $uri -Method PATCH -Headers $ServiceNowAuthenticationHeader -Body $incidentJson -ContentType "application/json;charset=utf-8" -SkipHttpErrorCheck

        if ($apiRes.BaseResponse.IsSuccessStatusCode) {
            $responseObj = $(ConvertFrom-Json $apiRes.Content)
            $innerStatusCode = $responseObj.result.answer.status

            if (![string]::IsNullOrWhiteSpace($innerStatusCode)) {
                try {
                    $innerStatusCode = [int]$innerStatusCode
                } catch {

                }
            }

            if (![string]::IsNullOrWhiteSpace($innerStatusCode) -and $innerStatusCode -ge 400) {
                $extInfo = [PSCustomObject]@{
                        TaskManager = 'ServiceNow'
                        Instance    = $this.InstanceURI
                        StatusCode  = $innerStatusCode
                        Content     = $responseObj.result.answer.message
                    };

                Add-Member -InputObject $extInfo -NotePropertyName "Payload" -NotePropertyValue $closeIncidentPayload

                $this.m_m365shhdb.AddActivityLogRecord(
                    [Guid]::Empty,
                    [TraceLogging]::CorrelationID,
                    '',
                    'app-' + [ConfigurationManager]::ClientId + '@' + [ConfigurationManager]::TenantDomain,
                    "CloseFailed",
                    'item://' + $ServiceCommunication.GetType().FullName.ToUpper() + '/' + $ServiceCommunication.Id,
                    'Task',
                    [Guid]::Empty,
                    $ServiceCommunication.Id,
                    'TaskManager',
                    [Guid]::Empty,
                    $extInfo,
                    $null
                )
            } else {
                $extInfo = [PSCustomObject]@{
                    TaskManager = 'ServiceNow'
                    Instance    = $this.InstanceURI
                    TaskId      = $Id
                    TaskUrl     = $this.GetTaskUrl($Id)
                };

                $this.m_m365shhdb.AddActivityLogRecord(
                    [Guid]::Empty,
                    [TraceLogging]::CorrelationID,
                    '',
                    'app-' + [ConfigurationManager]::ClientId + '@' + [ConfigurationManager]::TenantDomain,
                    "CloseSuccess",
                    'item://' + $ServiceCommunication.GetType().FullName.ToUpper() + '/' + $ServiceCommunication.Id,
                    'Task',
                    [Guid]::Empty,
                    $ServiceCommunication.Id,
                    'TaskManager',
                    [Guid]::Empty,
                    $extInfo,
                    $null
                )
            }
        } else {
            $extInfo = [PSCustomObject]@{
                TaskManager = 'ServiceNow'
                Instance    = $this.InstanceURI
                StatusCode  = $apiRes.BaseResponse.StatusCode.Value__
                Content     = $apiRes.Content
            };

            Add-Member -InputObject $extInfo -NotePropertyName "Payload" -NotePropertyValue $closeIncidentPayload

            $this.m_m365shhdb.AddActivityLogRecord(
                [Guid]::Empty,
                [TraceLogging]::CorrelationID,
                '',
                'app-' + [ConfigurationManager]::ClientId + '@' + [ConfigurationManager]::TenantDomain,
                "CloseFailed",
                'item://' + $ServiceCommunication.GetType().FullName.ToUpper() + '/' + $ServiceCommunication.Id,
                'Task',
                [Guid]::Empty,
                $ServiceCommunication.Id,
                'TaskManager',
                [Guid]::Empty,
                $extInfo,
                $null
            )
        }
    }

    hidden [System.Object] ProcessServiceNowRequest(
        [System.Object]$incident,
        [BaseMessage]$ServiceCommunication
    ) {
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceNowManager", "Incident", "snm109", "Entering method ServiceNowManager.ProcessServiceNowRequest()");
        $id = $incident."sys_id"

        $properties = $incident | Get-Member | Where-Object MemberType -eq "NoteProperty" | Select-Object -ExpandProperty Name
        $incidentProperties = New-Object -TypeName PSCustomObject
        foreach ($property in $properties) {
            if ($property.ToUpper() -ne "SYS_ID") {
                Add-Member -InputObject $incidentProperties -NotePropertyName $property -NotePropertyValue $incident."$property"
            }
        }

        $cloudEnvironment = $this.GetEnvironment($ServiceCommunication.Message.subscriptionId)

        Add-Member -InputObject $incidentProperties -NotePropertyName "caller_id" -NotePropertyValue $this.GetCallerId($cloudEnvironment)
        Add-Member -InputObject $incidentProperties -NotePropertyName "cmdb_ci" -NotePropertyValue $($cloudEnvironment.sys_id ? $cloudEnvironment.sys_id : "None")

        $ServiceNowAuthenticationHeader = $this.GetAuthHeader()

        $res = $(@{})
        $opType = '';

        Write-Information $(ConvertTo-Json $incidentProperties -Depth 5)

        $apiProperties = @{
            items = @()
        }

        if ($null -eq $id) {
            $opType = 'Create';
            [TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceNowManager", "Incident", "snm114", "Creating new incident.");
            Write-Information "Creating new item"
            $uri = $this.InstanceURI

            $item = New-Object -TypeName PSCustomObject
            Add-Member -InputObject $item -NotePropertyName "className" -NotePropertyValue "incident"
            Add-Member -InputObject $item -NotePropertyName "values" -NotePropertyValue $incidentProperties

            $apiProperties.items += $item;
            $incidentJson = $apiProperties | ConvertTo-Json -Depth 5
            [TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceNowManager", "Incident", "snm116", "Payload: $incidentJson");
            $apiRes = Invoke-WebRequest -Uri $uri -Method POST -Headers $ServiceNowAuthenticationHeader -Body $incidentJson -ContentType "application/json;charset=utf-8" -SkipHttpErrorCheck
        }
        else {
            $opType = 'Modify';
            [TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceNowManager", "Incident", "snm130", "Updating incident $id.");
            $uri = $this.InstanceURI
            Add-Member -InputObject $incidentProperties -NotePropertyName 'number' -NotePropertyValue $id

            $item = New-Object -TypeName PSCustomObject
            Add-Member -InputObject $item -NotePropertyName "className" -NotePropertyValue "incident"
            Add-Member -InputObject $item -NotePropertyName "values" -NotePropertyValue $incidentProperties

            $apiProperties.items += $item;
            $incidentJson = $apiProperties | ConvertTo-Json -Depth 5
            [TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceNowManager", "Incident", "snm131", "Payload: $incidentJson");
            $apiRes = Invoke-WebRequest -Uri $uri -Method PATCH -Headers $ServiceNowAuthenticationHeader -Body $incidentJson -ContentType "application/json;charset=utf-8" -SkipHttpErrorCheck
        }

        if ($apiRes.BaseResponse.IsSuccessStatusCode) {
            $responseObj = $(ConvertFrom-Json $apiRes.Content)
            $innerStatusCode = $responseObj.result.answer.status

            if (![string]::IsNullOrWhiteSpace($innerStatusCode)) {
                try {
                    $innerStatusCode = [int]$innerStatusCode
                } catch {

                }
            }

            if (![string]::IsNullOrWhiteSpace($innerStatusCode) -and $innerStatusCode -ge 400) {
                $op = ''
                switch ($opType) {
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

                $extInfo = [PSCustomObject]@{
                        TaskManager = 'ServiceNow'
                        Instance    = $this.InstanceURI
                        StatusCode  = $innerStatusCode
                        Content     = $responseObj.result.answer.message
                    };

                Add-Member -InputObject $extInfo -NotePropertyName "Payload" -NotePropertyValue $apiProperties

                $this.m_m365shhdb.AddActivityLogRecord(
                    [Guid]::Empty,
                    [TraceLogging]::CorrelationID,
                    '',
                    'app-' + [ConfigurationManager]::ClientId + '@' + [ConfigurationManager]::TenantDomain,
                    $op,
                    'item://' + $ServiceCommunication.GetType().FullName.ToUpper() + '/' + $ServiceCommunication.Id,
                    'Task',
                    [Guid]::Empty,
                    $ServiceCommunication.Id,
                    'TaskManager',
                    [Guid]::Empty,
                    $extInfo,
                    $null
                )

                throw "Couldn't perform '$opType' on task for communication $($ServiceCommunication.Id). Status code: $innerStatusCode. Message: $($responseObj.result.answer.message)"
            } else {
                $res = $responseObj.result.answer.items | Where-Object className -eq "incident" | Select-Object -First 1

                if ([string]::IsNullOrWhiteSpace($id)) {
                    $this.m_m365shhdb.AddActivityLogRecord(
                        [Guid]::Empty,
                        [TraceLogging]::CorrelationID,
                        '',
                        'app-' + [ConfigurationManager]::ClientId + '@' + [ConfigurationManager]::TenantDomain,
                        'Created',
                        'item://' + $ServiceCommunication.GetType().FullName.ToUpper() + '/' + $ServiceCommunication.Id,
                        'Task',
                        [Guid]::Empty,
                        $ServiceCommunication.Id,
                        'TaskManager',
                        [Guid]::Empty,
                        @{
                            TaskManager = 'ServiceNow'
                            Instance    = $this.InstanceURI
                            TaskId      = $res.value.number
                            TaskUrl     = $this.GetTaskUrl($res.value.number)
                        },
                        $null
                    )

                    $this.CloseIncident($ServiceCommunication, $res.value.number);
                }
                else {
                    $this.m_m365shhdb.AddActivityLogRecord(
                        [Guid]::Empty,
                        [TraceLogging]::CorrelationID,
                        '',
                        'app-' + [ConfigurationManager]::ClientId + '@' + [ConfigurationManager]::TenantDomain,
                        'Modified',
                        'item://' + $ServiceCommunication.GetType().FullName.ToUpper() + '/' + $ServiceCommunication.Id,
                        'Task',
                        [Guid]::Empty,
                        $ServiceCommunication.Id,
                        'TaskManager',
                        [Guid]::Empty,
                        @{
                            TaskManager = 'ServiceNow'
                            Instance    = $this.InstanceURI
                            TaskId      = $res.value.number
                            TaskUrl     = $this.GetTaskUrl($res.value.number)
                        },
                        $null
                    )

                    $this.CloseIncident($ServiceCommunication, $res.value.number);
                }
            }       
        }
        else {
            $op = ''
            switch ($opType) {
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

            $extInfo = [PSCustomObject]@{
                    TaskManager = 'ServiceNow'
                    Instance    = $this.InstanceURI
                    StatusCode  = $apiRes.BaseResponse.StatusCode.Value__
                    Content     = $apiRes.Content
                };

            Add-Member -InputObject $extInfo -NotePropertyName "Payload" -NotePropertyValue $apiProperties

            $this.m_m365shhdb.AddActivityLogRecord(
                [Guid]::Empty,
                [TraceLogging]::CorrelationID,
                '',
                'app-' + [ConfigurationManager]::ClientId + '@' + [ConfigurationManager]::TenantDomain,
                $op,
                'item://' + $ServiceCommunication.GetType().FullName.ToUpper() + '/' + $ServiceCommunication.Id,
                'Task',
                [Guid]::Empty,
                $ServiceCommunication.Id,
                'TaskManager',
                [Guid]::Empty,
                $extInfo,
                $null
            )

            throw "Couldn't perform '$opType' on task for communication $($ServiceCommunication.Id). Status code: $($apiRes.BaseResponse.StatusCode.Value__). Message: $($apiRes.Content)"
        }

        [TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceNowManager", "Incident", "snm134", "Exiting method ServiceNowManager.ProcessServiceNowRequest()");
        return $res
    }

    [void] SetTask(
        [BaseMessage]$ServiceCommunication,
        [System.Object]$Routing
    ) {
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceNowManager", "Incident", "snm150", "Entering method ServiceNowManager.SetServiceNowTicket()");
        $newItem = [string]::IsNullOrWhiteSpace($ServiceCommunication.WorkItemId)        
        $incident = $this.MetadataManager.MapData($ServiceCommunication, $Routing);

        $res = $this.ProcessServiceNowRequest($incident, $ServiceCommunication)

        $ServiceCommunication.WorkItemId = $res.value.number;
        $ServiceCommunication.WorkItemUrl = $this.GetTaskUrl($res.value.number);
        $ServiceCommunication.NewItem = $newItem;
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceNowManager", "Incident", "snm158", "Exiting method ServiceNowManager.SetServiceNowTicket()");
    }

    [void]LinkTasks(
        [BaseMessage]$MessageCenterMessage,
        [BaseMessage]$RoadmapMessage
    ) {
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceNowManager", "Incident", "snm4c0", "Entering method ServiceNowManager.LinkTasks()");

        $ServiceNowAuthenticationHeader = @{
            Accept        = 'application/json'
            Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $this.Username, $this.Password)))
        }

        $parentIncident = @{
            parent_incident = $MessageCenterMessage.WorkItemId
        }

        $incidentJson = $parentIncident | ConvertTo-Json -Depth 5

        [TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceNowManager", "Incident", "snm130", "Updating incident $($RoadmapMessage.WorkItemId). Setting $($MessageCenterMessage.WorkItemId) as a parent incident.");
        $uri = [string]::Format('{0}/api/now/table/incident/{1}', $this.InstanceURI, $RoadmapMessage.WorkItemId)
        $res = Invoke-RestMethod -Uri $uri -Method PATCH -Headers $ServiceNowAuthenticationHeader -Body $incidentJson -ContentType "application/json;charset=utf-8"

        [TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceNowManager", "Incident", "snm4c5", "Exiting method ServiceNowManager.LinkTasks()");
    }

    [void]AttachFile(
        [string]$Id,
        [string]$FileName,
        [System.Byte[]]$Stream
    ) {
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceNowManager", "Incident", "snm4c7", "Entering method ServiceNowManager.AttachFile()");

        $ServiceNowAuthenticationHeader = @{
            Accept        = 'application/json'
            Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $this.Username, $this.Password)))
        }
        $uri = [string]::Format("{0}/api/now/attachment/file?table_name=incident&table_sys_id={1}&file_name={2}", $this.InstanceURI, $Id, $FileName);

        [TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceNowManager", "Incident", "snm4c8", "Attaching file $FileName, length: $($stream.Length).");
        try {
            $res = Invoke-RestMethod -Uri $uri -Method Post -Body $Stream -Headers $ServiceNowAuthenticationHeader -ContentType "application/vnd.openxmlformats-officedocument.wordprocessingml.document"

            if ($null -ne $res) {
                [TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceNowManager", "Incident", "snm4ca", "File successfully uploaded. Url: $($res.result.download_link)");
            }
        }
        catch {
            [TraceLogging]::LogEvent([LoggingLevel]::Error, "ServiceNowManager", "Incident", "snm4cb", "File is not uploaded. Error: $($_.ErrorDetails.Message). Exception: $($_.Exception). Stack trace: $($_.ScriptStackTrace)");
        }

        [TraceLogging]::LogEvent([LoggingLevel]::Information, "ServiceNowManager", "Incident", "snm4cf", "Exiting method ServiceNowManager.AttachFile()");
    }
}