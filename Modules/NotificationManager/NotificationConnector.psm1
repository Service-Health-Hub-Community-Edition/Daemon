using module .\NotificationManagerBase.psm1
using module .\TeamsManager.psm1
using module .\TeamsNativeManager.psm1
using module .\LogicAppNotificationManager.psm1
using module .\ServiceBusNotificationManager.psm1
using module .\ACSEMailManager.psm1
using module ..\M365ServiceHealthHubDB.psm1

class NotificationTemplate
{
    hidden [M365ServiceHealthHubDB]$_mshh_db = [M365ServiceHealthHubDB]::new()
    [int]$Id
    [Guid]$ConnectorDefinition
    [string]$Entity
    [string]$Template

    NotificationTemplate()
    {

    }

    NotificationTemplate(
        [Guid]$ConnectorDefinition,
        [string]$Entity
    )
    {
        $templateDataRow = $this._mshh_db.GetNotificationTemplate($ConnectorDefinition, $Entity)
        if ($null -ne $templateDataRow)
        {
            $this.InitializeTemplate($templateDataRow);
        }
    }

    NotificationTemplate(
        [System.Object]$Template
    )
    {
        $this.InitializeTemplate($Template);
    }

    hidden [void] InitializeTemplate(
        [System.Object]$Template
    )
    {
        if ($null -ne $Template.ConnectorDefinition)
        {
            $this.Id = $Template.Id;
            $this.ConnectorDefinition = $Template.ConnectorDefinition;
            $this.Entity = $Template.Entity;
            $this.Template = $Template.Template;
        }
    }
}

class NotificationTemplateCollection
{
    hidden [M365ServiceHealthHubDB]$_mshh_db = [M365ServiceHealthHubDB]::new()
    [System.Collections.Generic.List[NotificationTemplate]]$Templates = $null;

    NotificationTemplateCollection()
    {
        $this.Templates = New-Object System.Collections.Generic.List[NotificationTemplate];
        $templateDataCollection = $this._mshh_db.GetNotificationTemplates();
        $this.InitializeTemplateCollection($templateDataCollection);
    }

    NotificationTemplateCollection(
        [string]$Component
    )
    {
        $this.Templates = New-Object System.Collections.Generic.List[NotificationTemplate];
        $templateDataCollection = $this._mshh_db.GetNotificationTemplates($Component);
        $this.InitializeTemplateCollection($templateDataCollection);
    }

    [void] InitializeTemplateCollection(
        $TemplateDataCollection
    )
    {
        if ($null -ne $TemplateDataCollection)
        {
            foreach ($template in $TemplateDataCollection)
            {
                $templateObj = [NotificationTemplate]::new();
                $templateObj.Id = $template.Id;
                $templateObj.ConnectorDefinition = $template.ConnectorDefinition;
                $templateObj.Entity = $template.Entity;
                $templateObj.Template = $template.Template;
                $this.Templates.Add($templateObj);
            }
        }
    }

    [NotificationTemplate] GetTemplate(
        [Guid]$ConnectorDefinition,
        [string]$Entity
    )
    {
        return $this.Templates | Where-Object { $_.ConnectorDefinition -eq $ConnectorDefinition -and $_.Entity -eq $Entity }
    }
}

class NotificationConnector
{
    hidden [M365ServiceHealthHubDB]$_mshh_db = [M365ServiceHealthHubDB]::new()
    [int]$Id
    [Guid]$ConnectorId
    [string]$Name
    [Guid]$Type
    [System.Object]$Configuration
    [string]$ConnectorTypeName
    [string]$Icon
    [bool]$System
    [System.Object]$ParameterDefinition
    [string]$Component    
    [NotificationManagerBase]$Instance
    [System.Object]$Template

    NotificationConnector()
    {

    }

    NotificationConnector(
        [Guid]$ConnectorId,
        [string]$Component,
        [bool]$IsSingleConnector
    )
    {
        $this.Component = $Component;
        [System.Object]$connector = $this._mshh_db.GetConnector($ConnectorId);
        $this.InitializeConnector($connector);
    }

    NotificationConnector(
        [System.Object]$Connector,
        [string]$Component
    )
    {
        $this.Component = $Component;
        $this.InitializeConnector($Connector);
    }

    [void]InitializeConnector(
        [System.Object]$Connector
    )
    {
        $this.Id = $Connector.Id;
        $this.ConnectorId = $Connector.ConnectorId;
        $this.Name = $Connector.Name;
        $this.Type = $Connector.Type;
        $this.Configuration = $Connector.Configuration | ConvertFrom-Json;
        $this.ConnectorTypeName = $Connector.ConnectorTypeName;
        $this.Icon = $Connector.Icon;
        $this.System = $Connector.System;
        $this.ParameterDefinition = $Connector.ParameterDefinition | ConvertFrom-Json;
        $this.Template = [NotificationTemplate]::new($this._mshh_db.GetNotificationTemplate($this.Type, $this.Component));
        $this.InitializeInstance();
    }

    [void]InitializeInstance()
    {
        [NotificationManagerBase]$nm = $null
        switch ($this.Type.ToString())
        {
            "2b650c59-bc1b-429c-9da9-ae09ba576cc7" { $nm = [TeamsManager]::new($this.Component, $this.Configuration, $this.Template.Template); }
            "df88e1e0-6af3-4b7e-9584-57340ca34caf" { $nm = [TeamsNativeManager]::new($this.Component, $this.Configuration, $this.Template.Template); }
            "e865a99d-44b2-4f3d-9c94-523c30fce3b0" { $nm = [LogicAppNotificationManager]::new($this.Component, $this.Configuration, $this.Template.Template);  }
            "a13f62e6-685a-47d6-91ee-f0cedffb3410" { $nm = [ServiceBusNotificationManager]::new($this.Component, $this.Configuration, $this.Template.Template); }
            "099ef26c-3030-46a4-aa89-bff0efe679f8" { $nm = [ACSEmailManager]::new($this.Component, $this.Configuration, $this.Template.Template); }
            default { throw "'$($this.ConnectorTypeName)' notification connector is not implemented." }
        }

        $this.Instance = $nm
    }
}