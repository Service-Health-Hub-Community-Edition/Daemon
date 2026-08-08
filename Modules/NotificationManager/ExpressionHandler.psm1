using module ..\Utility.psd1
using module ..\Utility.psm1
using module ..\BaseMessage.psm1
using module ..\Logging.psm1
using module ..\EntityMapping\BaseEntity.psm1
using module ..\EntityMapping\ReleaseMessageEntity.psm1
using module ..\EntityMapping\RoadmapEntity.psm1
using module ..\EntityMapping\ServiceIssueEntity.psm1
using module ..\EntityMapping\ServiceUpdateEntity.psm1
using module ..\EntityMapping\AzureServiceHealthAlertEntity.psm1
using module ..\Services\AzureTranslator.psm1
using module ..\M365ServiceHealthHubDB.psm1
using module .\RoutingManager.psm1
# $expression = "entity://StartTime/convertToDateTime/translate?convertToDateTime_format=dd.MM.yyyy hh:mm&convertToDateTime_localize"

class Parameter
{
    [string]$Name
    [System.Object]$Value
}

class Modifier
{
    [string]$Name
    [System.Collections.Generic.List[Parameter]]$Parameters
}

class Expression
{
    [bool]$IsExpression
    [string]$Value
    [string]$Element
    [System.Collections.Generic.List[Parameter]]$Parameters
    [System.Collections.Generic.List[Modifier]]$Modifiers
    [Route]$Route
    [BaseEntity]$Data

    Expression()
    {

    }

    Expression(
        [BaseEntity]$Data,
        [Route]$Route
    )
    {
        $this.Route = $Route;
        $this.Data = $Data;
    }

    hidden [void] ProcessContent(
        [string]$Content
    )
    {
        $expressionIdentifierCollection = @("entity://", "route://", "static://");
        $_isExpression = $false;

        foreach ($expressionIdentifier in $expressionIdentifierCollection)
        {
            if ($Content.Trim().StartsWith($expressionIdentifier))
            {
                $_isExpression = $true;
                break;
            }
        }
        if ($_isExpression){
            $expressionUri = [uri]::new($Content);
            $modifiersList = $expressionUri.Segments | % { $_.Trim("/"); }
            $modifierParamList = $expressionUri.Query.TrimStart("?").Split("&") | Group-Object { $_.Split("_")[0] }

            $modifierCollection = New-Object System.Collections.Generic.List[Modifier];
            $OtherParameters = New-Object System.Collections.Generic.List[Parameter];

            $processedGroups = @();

            foreach ($mItem in $modifiersList)
            {
                $processedGroups += $mItem;
                if (![string]::IsNullOrWhiteSpace($mItem))
                {
                    $modifierParamSet = $modifierParamList | Where-Object Name -eq $mItem
                    $modifierParameters = New-Object System.Collections.Generic.List[Parameter];

                    foreach ($modifierParameter in $modifierParamSet.Group)
                    {
                        $mp = $modifierParameter.TrimStart($modifierParamSet.Name + "_");
                        $modifierParameters.Add($this.GetParameterFromExpression($mp));            
                    }

                    $modifierItem = [Modifier]::new();
                    $modifierItem.Name = $mItem;
                    $modifierItem.Parameters = $modifierParameters;
                    $modifierCollection.Add($modifierItem);

                    # process other parameters
                    foreach ($modifierParamGroup in $modifierParamList)
                    {
                        if ($processedGroups -notcontains $modifierParamGroup.Name)
                        {
                            foreach ($modifierParam in $modifierParamGroup.Group)
                            {   
                                $OtherParameters.Add($this.GetParameterFromExpression($modifierParam));    
                            }
                        }
                    }
                }
            }

            $this.IsExpression = $true;
            $this.Value = $expressionUri.Scheme;
            $this.Element = $expressionUri.DnsSafeHost;
            $this.Parameters = $OtherParameters;
            $this.Modifiers = $modifierCollection;
        } else {

            $this.IsExpression = $false;
            $this.Value = $Content;
            $this.Element = "";
            $this.Modifiers = $null;
        }
    }

    hidden [Parameter]GetParameterFromExpression(
        [string]$ExpressionParameter
    )
    {
        $param = $null;
        if ($ExpressionParameter.IndexOf("=") -lt 0)
        {
            $param = [Parameter]::new();
            $param.Name = $ExpressionParameter;
            $param.Value = $true;
        }
        else 
        {
            $mpName = $ExpressionParameter.Substring(0, $ExpressionParameter.IndexOf("="));
            $mpValue = [System.Web.HttpUtility]::UrlDecode($ExpressionParameter.Substring($ExpressionParameter.IndexOf("=")+1));

            $param = [Parameter]::new();
            $param.Name = $mpName;
            $param.Value = $mpValue;
        }    
        
        return $param
    }

    hidden [string]Translate(
        [string]$Content,
        [string]$Language
    )
    {
        return $this.Translate($Content, $Language, $false);
    }

    hidden [string]Translate(
        [string]$Content,
        [string]$Language,
        [bool]$Html
    )
    {
        $result = $Content;

        $translator = [AzureTranslator]::new();
        try {
            $translation = $translator.Translate($Content, @($Language), $Html);
            $result = $translation[$Language];
        }
        catch {
            [TraceLogging]::LogEvent([LoggingLevel]::Error, "NotificationManager", "Data mapping", "nmg241", "Exception caught during translation to language '$Language'. Using original content. Exception: $($_.Exception). Error details: $($_.ErrorDetails). Stack trace: $($_.ScriptStackTrace)");
        }
        
        return $result;
    }

    <# [System.Object]RunMethod(
        [System.Object]
    )
    {

    }#>

    [System.Object]GetValue(
        [string]$Content
    )
    {
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "NotificationManager", "Data mapping", "nmg270", "Entering method NotificationManager.GetValue().");
        
        $this.ProcessContent($Content);

        # process metadata mapping
        $val = [string]::Empty;

        if (!$this.IsExpression)
        {
            $val = $this.Value;
        } else {
            switch ($this.Value.ToUpper())
            {
                "ENTITY" {
                    $val = $this.Data.GetProperty($this.Element);

                    foreach ($modifier in $this.Modifiers)
                    {
                        switch ($modifier.Name.Trim().ToUpper())
                        {
                            "CONVERTTOPLAINTEXT" {
                                #[TraceLogging]::LogEvent([LoggingLevel]::Information, "NotificationManager", "Data mapping", "nmg301", "Property: $Data. Expression: $Expression");
                                $val = [Utility]::ConvertToPlainText($val);
                            }
                            "TOADAPTIVECARDELEMENTS" {
                                $elements = [Utility]::ConvertHTMLToAdaptiveCardBody($val);
                                if ($null -eq $elements -or $elements.Count -eq 0)
                                {
                                    $elements = @(
                                        [PSCustomObject]@{
                                            type = "TextBlock"
                                            text = ""
                                            wrap = $true
                                        }
                                    )
                                }

                                if ($null -eq $elements.GetType().GetInterface("IEnumerable"))
                                {
                                    $val = @($elements)
                                }
                                else {
                                    $val = $elements
                                }
                            }
                            "DATETIMETOSTRING" {
                                $formatParam = $modifier.Parameters | Where-Object Name -eq "format" | Select-Object -First 1

                                [TraceLogging]::LogEvent([LoggingLevel]::Information, "NotificationManager", "Data mapping", "nmg303", "Modifier: $($modifier.Name). Format: $($formatParam.Value)");

                                if ($null -ne $formatParam -and ![string]::IsNullOrWhiteSpace($formatParam.Value))
                                {
                                    $val = [Utility]::DateTimeToString($this.Data.GetProperty($this.Element), $formatParam.Value);
                                } else {
                                    $val = [Utility]::DateTimeToString($this.Data.GetProperty($this.Element));
                                }
                            }
                            "BOOLTOYESNOSTRING" {
                                $val = [Utility]::BoolToString($val, "Yes", "No")
                            }
                            "GETSTATUSTHEMECOLOR" {
                                #[TraceLogging]::LogEvent([LoggingLevel]::Information, "NotificationManager", "Data mapping", "nmg304", "Property: $Data. Expression: $Expression");
                                $val = [Utility]::GetStatusThemeColor($this.Data.GetProperty($this.Element));
                            }
                            "PROCESSWORKITEMURL" {
                                #[TraceLogging]::LogEvent([LoggingLevel]::Information, "NotificationManager", "Data mapping", "nmg305", "Property: $Data. Expression: $Expression");
                                $val = $this.Route.HideWorkItemLink ? "" : $this.Data.GetProperty($this.Element);
                            }
                            "TRANSLATE" {
                                #[TraceLogging]::LogEvent([LoggingLevel]::Information, "NotificationManager", "Data mapping", "nmg306", "Property: $Data. Translation expression: $Expression");
                                if (![string]::IsNullOrWhiteSpace($this.Route.Language))
                                {
                                    $htmlParam = $modifier.Parameters | Where-Object Name -eq "html" | Select-Object -First 1
                                    #[TraceLogging]::LogEvent([LoggingLevel]::Information, "NotificationManager", "Data mapping", "nmg306a", "Language specified: $($Routing.Language)");
                                    $val = $this.Translate($val, $this.Route.Language, $($htmlParam -eq "true"));
                                } else {
                                    #[TraceLogging]::LogEvent([LoggingLevel]::Information, "NotificationManager", "Data mapping", "nmg307", "Language not specified. Using original content.");
                                }
                            }
                            "REPLACEIFNULL" {
                                #[TraceLogging]::LogEvent([LoggingLevel]::Information, "NotificationManager", "Data mapping", "nmg306", "Property: $Data. Translation expression: $Expression");
                                $altParam = $modifier.Parameters | Where-Object Name -eq "alt" | Select-Object -First 1
                                if ($null -eq $val)
                                {
                                    $val = $this.Data.GetProperty($altParam);
                                }
                            }
                        }
                    }
                }
                "STATIC" {
                    $val = $($this.Parameters | Where-Object Name -eq "value").Value;
                    foreach ($modifier in $this.Modifiers)
                    {
                        switch ($modifier.Name.Trim().ToUpper())
                        {
                            "TRANSLATE" {
                                #[TraceLogging]::LogEvent([LoggingLevel]::Information, "NotificationManager", "Data mapping", "nmg306", "Property: $Data. Translation expression: $Expression");
                                if (![string]::IsNullOrWhiteSpace($this.Route.Language))
                                {
                                    #[TraceLogging]::LogEvent([LoggingLevel]::Information, "NotificationManager", "Data mapping", "nmg306a", "Language specified: $($Routing.Language)");
                                    $val = $this.Translate($val, $this.Route.Language);
                                } else {
                                    #[TraceLogging]::LogEvent([LoggingLevel]::Information, "NotificationManager", "Data mapping", "nmg307", "Language not specified. Using original content.");
                                }
                            }
                        }
                    }
                }
                "ROUTE" {
                    if ($this.Element -eq "root")
                    {
                        $methodDefinition = $this.Modifiers[0];
                        if (![string]::IsNullOrWhiteSpace($methodDefinition.Name))
                        {
                            $params = @();
                            foreach ($param in $methodDefinition.Parameters)
                            {
                                $params += $param.Value;
                            }

                            try
                            {
                                [TraceLogging]::LogEvent([LoggingLevel]::Information, "NotificationManager", "Data mapping", "nmg307", "Executing method $($methodDefinition.Name), parameters: $($params -join ", ")");

                                $val = $this.Route.$($methodDefinition.Name).Invoke($params);
                            }
                            catch
                            {
                                # log error
                            }
                        }
                        
                    } else {
                        $val = $this.Route.$($this.Element);
                    }
                    
                    #[TraceLogging]::LogEvent([LoggingLevel]::Information, "NotificationManager", "Data mapping", "nmg312", "Property: $rawData. Routing value: $val");
                }
                default {
                }
            }
        }

        #[TraceLogging]::LogEvent([LoggingLevel]::Information, "NotificationManager", "Data mapping", "nmg394", "Exiting method NotificationManager.GetValue().");
        return $val
    }
}