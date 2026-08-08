using module .\Utility.psd1
using module .\Utility.psm1
using module .\BaseMessage.psm1
using module .\EntityMapping\BaseEntity.psm1
using module .\EntityMapping\ReleaseMessageEntity.psm1
using module .\EntityMapping\RoadmapEntity.psm1
using module .\EntityMapping\ServiceIssueEntity.psm1
using module .\EntityMapping\ServiceUpdateEntity.psm1
using module .\EntityMapping\AzureServiceHealthAlertEntity.psm1
using module .\EntityMapping\Office365EndpointsChangeEntity.psm1
using module .\EntityMapping\AzureUpdateEntity.psm1
using module .\EntityMapping\AzureAWSSupportTicketEntity.psm1
using module .\EntityMapping\D365PowerPlatformReleaseEntity.psm1
using module .\EntityMapping\CommonDataConnectorAlertV1Entity.psm1
using module .\M365ServiceHealthHubDB.psm1

class RulesEngine
{
    [System.Object[]]$Routing = $null
    [System.Object[]]$Exclusions = $null
    [System.Object[]]$TaskRouting = $null
    hidden [M365ServiceHealthHubDB]$m_m365shhdb = [M365ServiceHealthHubDB]::new();

    RulesEngine(
        [string]$Component
    )
    {
        $rules = $this.m_m365shhdb.GetSyncConfigEntry($Component, "routing") | ConvertFrom-Json
        $this.Routing = $rules.Routing | Sort-Object Id
        $this.Exclusions = $rules.Exclusions | Sort-Object Id
        $this.TaskRouting = $rules.TaskRouting | Sort-Object Id
    }

    hidden [System.Object[]] GetMatch(
        $Rule,
        $Data
    )
    {
        if ($null -eq $rule.Conditions -or $rule.Conditions.Count -eq 0)
        {
            return $true
        }

        $match = $false;
        $previousLogicOperator = "or"

        foreach ($condition in $Rule.Conditions)
        {
            if ([string]::IsNullOrWhiteSpace($condition.LogicOperator)) {
                $currentLogicOperator = "or"
            } else {
                $currentLogicOperator = $condition.LogicOperator.Trim().ToLower()
            }

            $currentMatch = $false

            switch($condition.Operator.Trim().ToLower()){
                "eq"   { $Data."$($condition.Property)" | % { $currentMatch = $currentMatch -or ($_ -eq $condition.Value)} }
                "ne"   { $Data."$($condition.Property)" | % { $currentMatch = $currentMatch -or ($_ -ne $condition.Value)} }
                "gt"   { $Data."$($condition.Property)" | % { $currentMatch = $currentMatch -or ($_ -gt $condition.Value)} }
                "ge"   { $Data."$($condition.Property)" | % { $currentMatch = $currentMatch -or ($_ -ge $condition.Value)} }
                "lt"   { $Data."$($condition.Property)" | % { $currentMatch = $currentMatch -or ($_ -lt $condition.Value)} }
                "le"   { $Data."$($condition.Property)" | % { $currentMatch = $currentMatch -or ($_ -le $condition.Value)} }
                "like" { $Data."$($condition.Property)" | % { $currentMatch = $currentMatch -or ($_ -like $condition.Value)} }
                "notlike" { $Data."$($condition.Property)" | % { $currentMatch = $currentMatch -or ($_ -notlike $condition.Value)} }
                "match" { $Data."$($condition.Property)" | % { $currentMatch = $currentMatch -or ($_ -match $condition.Value)} }
                "notmatch" { $Data."$($condition.Property)" | % { $currentMatch = $currentMatch -or ($_ -notmatch $condition.Value)} }
                "contains" { $Data."$($condition.Property)" | % { $currentMatch = $currentMatch -or ($_ -contains $condition.Value)} }
                "notcontains" { $Data."$($condition.Property)" | % { $currentMatch = $currentMatch -or ($_ -notcontains $condition.Value)} }
                "in"   { $Data."$($condition.Property)" | % { $currentMatch = $currentMatch -or ($_ -in $condition.Values)} }
                "notin"   { $Data."$($condition.Property)" | % { $currentMatch = $currentMatch -or ($_ -notin $condition.Values)} }          
            }

            switch($previousLogicOperator)
            {
                "or" { $match = $match -or $currentMatch }
                "and" { $match = $match -and $currentMatch }
            }
            $previousLogicOperator = $currentLogicOperator
        }

        return $match
    }

    hidden [System.Object] GetEntity(
        [BaseMessage]$NotificationData
    )
    {
        $entityMapper = $null;
        $dataType = $NotificationData.GetType().Name;
        switch ($dataType)
        {
            "ReleaseMessage" { $entityMapper = [ReleaseMessageEntity]::new($NotificationData); }
            "RoadmapCommunication" { $entityMapper = [RoadmapEntity]::new($NotificationData); }
            "ServiceUpdateMessage" { $entityMapper = [ServiceUpdateEntity]::new($NotificationData); }
            "ServiceHealthIssue" { $entityMapper = [ServiceIssueEntity]::new($NotificationData); }
            "AzureServiceHealthAlert" { $entityMapper = [AzureServiceHealthAlertEntity]::new($NotificationData); }
            "Office365EndpointsChange" { $entityMapper = [Office365EndpointsChangeEntity]::new($NotificationData); }
            "AzureUpdate" { $entityMapper = [AzureUpdateEntity]::new($NotificationData); }
            "AzureAWSSupportTicket" { $entityMapper = [AzureAWSSupportTicketEntity]::new($NotificationData); }
            "D365PowerPlatformRelease" { $entityMapper = [D365PowerPlatformReleaseEntity]::new($NotificationData); }
            "CommonDataConnectorAlertV1" { $entityMapper = [CommonDataConnectorAlertV1Entity]::new($NotificationData); }
            default { $entityMapper = [BaseEntity]::new($NotificationData); }
        }
        return $($null -eq $entityMapper ? $null : $entityMapper.m_properties);
    }

    [System.Object[]] GetExclusionMatches([BaseMessage]$NotificationData)
    {
        $entityData = $this.GetEntity($NotificationData);

        $res = @()

        foreach ($rule in $this.Exclusions)
        {
            $match = $this.GetMatch($rule, $entityData)
            if ($match)
            {
                $res += $rule;
            }
        }

        return $null
    }

    [System.Object[]] GetRoutingMatches([BaseMessage]$NotificationData)
    {
        $entityData = $this.GetEntity($NotificationData);

        $res = @()

        $ex = $this.GetExclusionMatches($NotificationData);

        if ($ex.Count -gt 0)
        {
            return $null;
        }

        foreach ($rule in $this.Routing)
        {
            $match = $this.GetMatch($rule, $entityData)
            if ($match)
            {
                $res += $rule;

                $stopProcessingOnMatch = [Utility]::ParseBooleanValue($rule.StopProcessingOnMatch, $true)
                
                if ($stopProcessingOnMatch)
                {
                    return $res
                }
            }
        }

        return $null
    }

    [System.Object[]] GetTaskRoutingMatches([BaseMessage]$NotificationData)
    {
        $entityData = $this.GetEntity($NotificationData);

        $res = @()

        $ex = $this.GetExclusionMatches($NotificationData);

        if ($ex.Count -gt 0)
        {
            return $null;
        }

        foreach ($rule in $this.TaskRouting)
        {
            $match = $this.GetMatch($rule, $entityData)
            if ($match)
            {
                # return only first routing rule as we support creating only one task per communication
                return $rule;
            }
        }

        return $null
    }
}