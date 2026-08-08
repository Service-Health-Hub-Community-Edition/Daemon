
using module ..\BaseMessage.psm1
using module ..\Logging.psm1
using module ..\ConfigurationManager.psm1
using module ..\M365ServiceHealthHubDB.psm1

class TaskManagerBase
{
    hidden [M365ServiceHealthHubDB]$m_m365shhdb = [M365ServiceHealthHubDB]::new();

    TaskManagerBase()
    {

    }

    TaskManagerBase(
        [string]$Component
    )
    {

    }

    [void] SetTask(
        [BaseMessage]$ServiceCommunication,
        [System.Object]$Routing
    )
    {

    }

    [void]LinkTasks(
        [BaseMessage]$MessageCenterMessage,
        [BaseMessage]$RoadmapMessage
    )
    {

    }

    [void]AttachFile(
        [string]$Id,
        [string]$FileName,
        [System.Byte[]]$Stream
    )
    {

    }
}