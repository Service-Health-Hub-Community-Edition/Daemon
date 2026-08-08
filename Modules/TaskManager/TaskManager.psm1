using module .\TaskManagerBase.psm1
using module .\AzureDevOpsManager.psm1
using module .\ServiceNowManager.psm1
using module .\JiraManager.psm1
using module .\LogicAppManager.psm1

class TaskManager
{
    static [TaskManagerBase]CreateInstance(
        [string]$TaskManager,
        [string]$Component
    )
    {
        [TaskManagerBase]$tm = $null
        switch ($TaskManager)
        {
            "AzureDevOps" { $tm = [AzureDevOpsManager]::new($Component); }
            "LogicApps" { $tm = [LogicAppManager]::new($Component);  }
            "ServiceNow" { $tm = [ServiceNowManager]::new($Component);  }
            "Jira" { $tm = [JiraManager]::new($Component);  }
            default { throw "$TaskManager support is not implemented yet." }
        }

        return $tm;
    }
}