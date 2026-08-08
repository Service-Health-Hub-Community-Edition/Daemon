using module ..\Modules\M365ServiceHealthHubDB.psm1
using module ..\Modules\Logging.psm1
using module ..\Modules\ConfigurationManager.psm1
using module ..\Modules\SystemAlert.psm1
using module ..\Modules\NotificationManager\NotificationManager.psm1

# Input bindings are passed in via param block.
param($Timer)

[TraceLogging]::InitializeCorrelationID();
$global:systemAlert = [NotificationManager]::new("SystemAlert");

[TraceLogging]::LogEvent([LoggingLevel]::Information, "TenantReports", "Main", "awd100", "Initializing Admin weekly digest job.");
$db = [M365ServiceHealthHubDB]::new();
$component = "SystemAlert";
$componentId = $($db.GetComponents().Rows | Where-Object InternalName -eq $component).ComponentId

$db.AddActivityLogRecord(
		[Guid]::Empty,
		[TraceLogging]::CorrelationID,
		'',
		'app-' + [ConfigurationManager]::ClientId + '@' + [ConfigurationManager]::TenantDomain,
		'JobStarted',
		'item://' + $component,
		'Job',
		[Guid]::Empty,
		"",
		$component,
		$componentId,
		$null,
		$null
	);

try {
    [TraceLogging]::LogEvent([LoggingLevel]::Information, "TenantReports", "Main", "awd101", "Retrieving activity log entries for the past week.");
    $res = $db.GetActivityLogEntries(7);
    [TraceLogging]::LogEvent([LoggingLevel]::Information, "TenantReports", "Main", "awd102", "$($res.Count) items retrieved. Normalizing items.");

    foreach ($r in $res)
    {                                                                                                              
        if ([string]::IsNullOrWhitespace($r.InternalName))
        {
            $internalName = $r.ActivityLogItem.Split('/')[2]
            if (![string]::IsNullOrWhiteSpace($internalName))
            {
                $r.InternalName = $internalName
                $displayName = $res | Where-Object InternalName -eq $internalName | Select-Object -ExpandProperty Name -First 1
                $r.Name = $displayName
            }
        }
    }

    [TraceLogging]::LogEvent([LoggingLevel]::Information, "TenantReports", "Main", "awd103", "Grouping activity items.");

    $jobGroup = $res | Group-Object Name
    $jobReport = @()

    foreach ($job in $jobGroup)
    {
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "TenantReports", "Main", "awd105", "Processing job $($job.Name).");
        $name = $job.Name
        $groupByType = $job.Group | Group-Object ItemType
        $individualJobReport = @()
        foreach ($itemTypeGroup in $groupByType)
        {
            $itemType = $itemTypeGroup.Name
            $groupByActivity = $itemTypeGroup.Group | Group-Object Activity
            foreach ($activity in $groupByActivity)
            {
                $individualJobReport += [PSCustomObject]@{
                    Type = $itemType
                    Action = $activity.Name
                    Count = $activity.Count
                }
            }
        }

        $jobReport += [PSCustomObject]@{
            Name = $name
            Activity = $individualJobReport
        }
    }

    [TraceLogging]::LogEvent([LoggingLevel]::Information, "TenantReports", "Main", "awd10a", "Grouping error items.");

    $errors = $res | Where-Object {$_.Activity -like "*Fail*" -or $_.Activity -like "*Error*" }
    $jobGroup = $errors | Group-Object Name
    $errorJobReport = @()

    foreach ($job in $jobGroup)
    {
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "TenantReports", "Main", "awd10c", "Processing job $($job.Name).");
        $name = $job.Name
        $groupByType = $job.Group | Group-Object ItemType
        foreach ($itemTypeGroup in $groupByType)
        {
            $itemType = $itemTypeGroup.Name
            $groupByActivity = $itemTypeGroup.Group | Group-Object Activity
            foreach ($activity in $groupByActivity)
            {
                $errorJobReport += [PSCustomObject]@{
                    Name = $name
                    Type = $itemType
                    Action = $activity.Name
                    Count = $activity.Count
                }
            }
        }
    }

    [TraceLogging]::LogEvent([LoggingLevel]::Information, "TenantReports", "Main", "awd112", "Creating report.");
    $errorReport = ""
    $errorReportAdaptiveCard = [PSCustomObject]@{
        type = "Table"
        firstRowAsHeaders = $true
        columns = @(
            [PSCustomObject]@{
                width = 2
            },
            [PSCustomObject]@{
                width = 1
            },
            [PSCustomObject]@{
                width = 1
            },
            [PSCustomObject]@{
                width = 1
            }
        )
        rows = [System.Collections.Generic.List[System.Object]]::new()
    }

    if ($errorJobReport.Count -gt 0)
    {
        $headerStrings = @("Name", "Type", "Action", "Count")
        $errorReport = '<table style="border:none;border-collapse:collapse;border-spacing:0;">
        <thead style="font-weight:bold;text-align:left;vertical-align:middle;border-style:solid;border-width:0px;border-bottom:1px solid;
        font-family:Arial, sans-serif;font-size:12px;font-weight:bold;overflow:hidden;padding:10px 5px;word-break:normal;">
            <tr>
        '

        $headerRowAC = [PSCustomObject]@{
            type = "TableRow"
            cells = [System.Collections.Generic.List[System.Object]]::new()
        }

        foreach ($headerString in $headerStrings)
        {
            $errorReport += '<th style="padding:10px 5px">'
            $errorReport += $headerString
            $errorReport += '</th>'

            $headerRowAC.cells.Add([PSCustomObject]@{
                type = "TableCell"
                items = @(
                    [PSCustomObject]@{
                        type = "TextBlock"
                        text = $headerString
                        wrap = $true
                        weight = "Bolder"
                    }
                )
            })
        }

        $errorReportAdaptiveCard.rows.Add($headerRowAC)

        $errorReport += '
            </tr>
        </thead>
        <tbody style="font-weight:bold;text-align:left;vertical-align:middle;border-style:solid;border-width:0px;
        font-family:Arial, sans-serif;font-size:12px;font-weight:normal;overflow:hidden;padding:10px 5px;word-break:normal;">'

        $td = '<td style="padding:10px 5px">'
        $tdEnd = '</td>' 

        foreach ($errorJob in $errorJobReport)
        {
            $errorReport += '<tr>'
            $errorReport += $td + $errorJob.Name + $tdEnd;
            $errorReport += $td + $errorJob.Type + $tdEnd;
            $errorReport += $td + $errorJob.Action + $tdEnd;
            $errorReport += $td + $errorJob.Count + $tdEnd;
            $errorReport += '</tr>'

            $errorReportRowAC = [PSCustomObject]@{
                type = "TableRow"
                cells = [System.Collections.Generic.List[System.Object]]::new()
            }

            $errorReportRowAC.cells.Add([PSCustomObject]@{
                type = "TableCell"
                items = @(
                    [PSCustomObject]@{
                        type = "TextBlock"
                        text = $null -eq $errorJob.Name ? "" : $errorJob.Name.ToString()
                        wrap = $true
                    }
                )
            })

            $errorReportRowAC.cells.Add([PSCustomObject]@{
                type = "TableCell"
                items = @(
                    [PSCustomObject]@{
                        type = "TextBlock"
                        text = $null -eq $errorJob.Type ? "" : $errorJob.Type.ToString()
                        wrap = $true
                    }
                )
            })

            $errorReportRowAC.cells.Add([PSCustomObject]@{
                type = "TableCell"
                items = @(
                    [PSCustomObject]@{
                        type = "TextBlock"
                        text = $null -eq $errorJob.Action ? "" : $errorJob.Action.ToString()
                        wrap = $true
                    }
                )
            })

            $errorReportRowAC.cells.Add([PSCustomObject]@{
                type = "TableCell"
                items = @(
                    [PSCustomObject]@{
                        type = "TextBlock"
                        text = $null -eq $errorJob.Count ? "" : $errorJob.Count.ToString()
                        wrap = $true
                    }
                )
            })

            $errorReportAdaptiveCard.rows.Add($errorReportRowAC)
        }

        $errorReport += '</tbody>
                        </table>'
    } else {
        $errorReport = "<br/><p>No errors found.</p>"
        $errorReportAdaptiveCard = [PSCustomObject]@{
            type = "TextBlock"
            text = "No errors found."
            wrap = $true
        }
    }

    $activityReport = ""
    $activityReportAdaptiveCard = [PSCustomObject]@{
        type = "Table"
        firstRowAsHeaders = $true
        columns = @(
            [PSCustomObject]@{
                width = 3
            },
            [PSCustomObject]@{
                width = 1
            },
            [PSCustomObject]@{
                width = 1
            },
            [PSCustomObject]@{
                width = 1
            },
            [PSCustomObject]@{
                width = 1
            }
        )
        rows = [System.Collections.Generic.List[System.Object]]::new()
    }

    if ($jobReport.Count -gt 0)
    {
        $headerStrings = @("Name", "Runs", "New tasks", "Updated tasks", "Notifications")
        $activityReport = '<table style="border:none;border-collapse:collapse;border-spacing:0;">
        <thead style="font-weight:bold;text-align:left;vertical-align:middle;border-style:solid;border-width:0px;border-bottom:1px solid;
        font-family:Arial, sans-serif;font-size:12px;font-weight:bold;overflow:hidden;padding:10px 5px;word-break:normal;">
            <tr>
        '

        $headerRowAC = [PSCustomObject]@{
            type = "TableRow"
            cells = [System.Collections.Generic.List[System.Object]]::new()
        }
        foreach ($headerString in $headerStrings)
        {
            $activityReport += '<th style="padding:10px 5px">'
            $activityReport += $headerString
            $activityReport += '</th>'

            $headerRowAC.cells.Add([PSCustomObject]@{
                type = "TableCell"
                items = @(
                    [PSCustomObject]@{
                        type = "TextBlock"
                        text = $headerString
                        wrap = $true
                        weight = "Bolder"
                    }
                )
            })
        }

        $activityReportAdaptiveCard.rows.Add($headerRowAC)

        $activityReport += '
            </tr>
        </thead>
        <tbody style="font-weight:bold;text-align:left;vertical-align:middle;border-style:solid;border-width:0px;
        font-family:Arial, sans-serif;font-size:12px;font-weight:normal;overflow:hidden;padding:10px 5px;word-break:normal;">'

        $td = '<td style="padding:10px 5px">'
        $tdEnd = '</td>'

        foreach ($element in $jobReport)
        {
            $startedJobs = $($element.Activity | Where-Object { $_.Type -eq 'Job' -and $_.Action -eq 'JobStarted' } | Select-Object -ExpandProperty Count -First 1)
            $createdTasks = $($element.Activity | Where-Object { $_.Type -eq 'Task' -and $_.Action -eq 'Created' } | Select-Object -ExpandProperty Count -First 1)
            $modifiedTasks = $($element.Activity | Where-Object { $_.Type -eq 'Task' -and $_.Action -eq 'Modified' } | Select-Object -ExpandProperty Count -First 1)
            $notificationsSent = $($element.Activity | Where-Object { $_.Type -eq 'Notification' -and $_.Action -eq 'NotificationSent' } | Select-Object -ExpandProperty Count -First 1)
            $activityReport += '<tr>'
            $activityReport += $td + $element.Name + $tdEnd;
            $activityReport += $td + $startedJobs + $tdEnd;
            $activityReport += $td + $createdTasks + $tdEnd;
            $activityReport += $td + $modifiedTasks + $tdEnd;
            $activityReport += $td + $notificationsSent + $tdEnd;
            $activityReport += '</tr>'

            $activityReportRowAC = [PSCustomObject]@{
                type = "TableRow"
                cells = [System.Collections.Generic.List[System.Object]]::new()
            }

            $activityReportRowAC.cells.Add([PSCustomObject]@{
                type = "TableCell"
                items = @(
                    [PSCustomObject]@{
                        type = "TextBlock"
                        text = $null -eq $element.Name ? "" : $element.Name.ToString()
                        wrap = $true
                    }
                )
            })

            $activityReportRowAC.cells.Add([PSCustomObject]@{
                type = "TableCell"
                items = @(
                    [PSCustomObject]@{
                        type = "TextBlock"
                        text = $null -eq $startedJobs ? "" : $startedJobs.ToString()
                        wrap = $true
                    }
                )
            })

            $activityReportRowAC.cells.Add([PSCustomObject]@{
                type = "TableCell"
                items = @(
                    [PSCustomObject]@{
                        type = "TextBlock"
                        text = $null -eq $createdTasks ? "" : $createdTasks.ToString()
                        wrap = $true
                    }
                )
            })

            $activityReportRowAC.cells.Add([PSCustomObject]@{
                type = "TableCell"
                items = @(
                    [PSCustomObject]@{
                        type = "TextBlock"
                        text = $null -eq $modifiedTasks ? "" : $modifiedTasks.ToString()
                        wrap = $true
                    }
                )
            })

            $activityReportRowAC.cells.Add([PSCustomObject]@{
                type = "TableCell"
                items = @(
                    [PSCustomObject]@{
                        type = "TextBlock"
                        text = $null -eq $notificationsSent ? "" : $notificationsSent.ToString()
                        wrap = $true
                    }
                )
            })

            $activityReportAdaptiveCard.rows.Add($activityReportRowAC)
        }

        $activityReport += '</tbody>
                        </table>'
    } else {
        $activityReport = "<p>No activity found</p>"
        $activityReportAdaptiveCard = [PSCustomObject]@{
            type = "TextBlock"
            text = "No activity found"
            wrap = $true
        }
    }

    $jobTitle = "Service Health Hub - Weekly job report ($([DateTime]::UtcNow.AddDays(-7).ToString("d")) - $([DateTime]::UtcNow.ToString("d")))"
    $errorStatisticsHeader = "Error statistics:"
    $activityReportHeader = "Activity report:"
    $title = "Job report for $([DateTime]::UtcNow.AddDays(-7).ToString("d")) - $([DateTime]::UtcNow.ToString("d"))"
    $type = "Digest"
    $description = "<h2>$jobTitle</h2><p><b>$errorStatisticsHeader</b><br/>&nbsp;<p>" + $errorReport
    $description += "<p><br/>&nbsp;</p>" + "<p><b>$activityReportHeader</b><br/>&nbsp;<p>" + $activityReport
    $timestamp = [DateTime]::UtcNow

    $adaptiveCardBody = [System.Collections.Generic.List[System.Object]]::new()

    $adaptiveCardBody.Add([PSCustomObject]@{
        type = "TextBlock"
        text = $jobTitle
        size = "Medium"
        weight = "Bolder"
        spacing = "Large"
        wrap = $true
    })

    $adaptiveCardBody.Add([PSCustomObject]@{
        type = "TextBlock"
        text = $errorStatisticsHeader
        size = "Default"
        weight = "Bolder"
        spacing = "Large"
        wrap = $true
    })

    $adaptiveCardBody.Add($errorReportAdaptiveCard)

    $adaptiveCardBody.Add([PSCustomObject]@{
        type = "TextBlock"
        text = $activityReportHeader
        size = "Default"
        weight = "Bolder"
        spacing = "Large"
        wrap = $true
    })

    $adaptiveCardBody.Add($activityReportAdaptiveCard)

    [TraceLogging]::LogEvent([LoggingLevel]::Information, "TenantReports", "Main", "awd119", "Creating alert object.");

    $alert = [SystemAlert]::new()
    $alert.Message = [PSCustomObject]@{                                      
        Title = $title
        Type = $type
        Description = $description
        AdaptiveCardBody = $adaptiveCardBody
        Timestamp = $timestamp
    }

    [TraceLogging]::LogEvent([LoggingLevel]::Information, "TenantReports", "Main", "awd11b", "Initializing notification manager.");
    $nm = [NotificationManager]::new($component)
    [TraceLogging]::LogEvent([LoggingLevel]::Information, "TenantReports", "Main", "awd11c", "Sending report.");
    $nm.SendMessage($alert);

    $db.AddActivityLogRecord(
        [Guid]::Empty,
        [TraceLogging]::CorrelationID,
        '',
        'app-' + [ConfigurationManager]::ClientId + '@' + [ConfigurationManager]::TenantDomain,
        'JobCompleted',
        'item://' + $component,
        'Job',
        [Guid]::Empty,
        "",
        $component,
        $componentId,
        $null,
        $null
    );

    [TraceLogging]::LogEvent([LoggingLevel]::Information, "TenantReports", "Main", "awd11f", "All operations completed successfully.");
} catch {
    $db.AddActivityLogRecord(
        [Guid]::Empty,
        [TraceLogging]::CorrelationID,
        '',
        'app-' + [ConfigurationManager]::ClientId + '@' + [ConfigurationManager]::TenantDomain,
        'JobFailed',
        'item://' + $component,
        'Job',
        [Guid]::Empty,
        "",
        $component,
        $componentId,
        $($null -ne $_.Exception ? $_.Exception.ToString() : $_.ToString()),
        $null
    );

    [TraceLogging]::LogEvent([LoggingLevel]::Error, "TenantReports", "Main", "awd12f", "An issue occured: $_");
    throw;
}
