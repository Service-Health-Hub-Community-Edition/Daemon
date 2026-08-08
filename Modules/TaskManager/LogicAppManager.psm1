using module ..\BaseMessage.psm1
using module ..\ConfigurationManager.psm1
using module ..\Utility.psd1
using module ..\Utility.psm1
using module ..\Logging.psm1
using module ..\MetadataManager.psm1
using module .\TaskManagerBase.psm1
using module ..\SystemAlert.psm1

class LogicAppManager:TaskManagerBase
{
    [string]$Endpoint = [string]::Empty
    hidden [MetadataManager]$MetadataManager = $null;

    LogicAppManager()
    {

    }

    LogicAppManager(
        [string]$Component
    )
    {
        $this.Endpoint = [ConfigurationManager]::GetTaskManagerConfigParameter('LogicApps.Endpoint');
        if (![string]::IsNullOrWhiteSpace($this.Endpoint))
        {
            $this.Endpoint.Trim().TrimEnd("/");
        }

        $this.MetadataManager = [MetadataManager]::new($Component);
    }

    hidden [System.Object] ProcessLogicAppRequest(
        [string]$TicketData,
        [BaseMessage]$ServiceCommunication
    )
    {
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "LogicAppManager", "Incident", "lap109", "Entering method LogicAppManager.ProcessLogicAppRequest()");
        $task = ConvertFrom-Json $TicketData
        $id = $task."Id"

        $properties = $task | Get-Member | Where-Object MemberType -eq "NoteProperty" | Select-Object -ExpandProperty Name
        $taskProperties = @{}
        foreach ($property in $properties)
        {
            Add-Member -InputObject $taskProperties -NotePropertyName $property -NotePropertyValue $task.$property
        }

        $taskJson = $taskProperties | ConvertTo-Json -Depth 5
        $apiRes = Invoke-WebRequest -Uri $this.Endpoint -Method POST -Body $taskJson -ContentType "application/json;charset=utf-8" -SkipHttpErrorCheck
        $res = $(@{})
        $opType = [string]::IsNullOrWhiteSpace($id) ? 'Create' : 'Modify';

        if ($apiRes.BaseResponse.IsSuccessStatusCode)
        {
            $res = $(ConvertFrom-Json $apiRes.Content)
            if ([string]::IsNullOrWhiteSpace($id))
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
                        TaskManager = 'LogicApp'
                        TaskId = $res.id
                        TaskUrl = $res.url
                    },
                    $null
                )
            } else {
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
                        TaskManager = 'LogicApp'
                        TaskId = $res.id
                        TaskUrl = $res.url
                    },
                    $null
                )
            }       
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
                $opType,
                'item://' + $ServiceCommunication.GetType().FullName.ToUpper() + '/' + $ServiceCommunication.Id,
                'Task',
                [Guid]::Empty,
                $ServiceCommunication.Id,
                'TaskManager',
                [Guid]::Empty,
                @{
                    TaskManager = 'LogicApp'
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
                [TraceLogging]::LogEvent([LoggingLevel]::Error, "LogicAppManager", "Incident", "lam132", "Couldn't send system alert. Exception: $_");
            }

            throw "Couldn't perform '$opType' on task for communication $($ServiceCommunication.Id). Status code: $($apiRes.BaseResponse.StatusCode.Value__). Message: $($apiRes.Content)"
        }

        [TraceLogging]::LogEvent([LoggingLevel]::Information, "LogicAppManager", "Incident", "lap134", "Exiting method LogicAppManager.ProcessLogicAppRequest()");
        return $res
    }

    [void] SetTask(
        [BaseMessage]$ServiceCommunication,
        [System.Object]$Routing
    )
    {
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "LogicAppManager", "Incident", "lap150", "Entering method LogicAppManager.SetLogicAppTicket()");
        $newItem = [string]::IsNullOrWhiteSpace($ServiceCommunication.WorkItemId)        
        $task = $this.MetadataManager.MapData($ServiceCommunication, $Routing);
        
        $body = ConvertTo-Json -InputObject $task -Depth 5
        $res = $this.ProcessLogicAppRequest($body, $ServiceCommunication)

        $ServiceCommunication.WorkItemId = $res.id;
        $ServiceCommunication.WorkItemUrl = $res.url;
        $ServiceCommunication.NewItem = $newItem;
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "LogicAppManager", "Incident", "lap158", "Exiting method LogicAppManager.SetLogicAppTicket()");
    }

    [void]LinkTasks(
        [BaseMessage]$MessageCenterMessage,
        [BaseMessage]$RoadmapMessage
    )
    {
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "LogicAppManager", "Incident", "lap4c0", "Entering method LogicAppManager.LinkTasks()");
        [TraceLogging]::LogEvent([LoggingLevel]::Warning, "LogicAppManager", "Incident", "lap4c0", "Linking tasks via LogicApps is currently not supported. Skipping.");
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "LogicAppManager", "Incident", "lap4c5", "Exiting method LogicAppManager.LinkTasks()");
    }

    [void]AttachFile(
        [string]$Id,
        [string]$FileName,
        [System.Byte[]]$Stream
    )
    {
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "LogicAppManager", "Incident", "lap4c7", "Entering method LogicAppManager.AttachFile()");
        [TraceLogging]::LogEvent([LoggingLevel]::Warning, "LogicAppManager", "Incident", "lap4c9", "Attaching files via LogicApps is currently not supported. Skipping.");
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "LogicAppManager", "Incident", "lap4cf", "Exiting method LogicAppManager.AttachFile()");
    }
}