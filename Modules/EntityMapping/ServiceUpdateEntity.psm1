using module ..\Utility.psd1
using module ..\Utility.psm1
using module ..\Logging.psm1
using module ..\BaseMessage.psm1
using module .\BaseEntity.psm1
using module ..\Services\AzureLanguageServices.psm1

class ServiceUpdateEntity: BaseEntity
{
    ServiceUpdateEntity(
        [BaseMessage]$Message
    ): base($Message)
    {
        
    }

    [void]Initialize(
        [BaseMessage]$Message
    )
    {
        ([BaseEntity]$this).Initialize($Message);

        if ($null -ne $Message.Message)
        {
            $textSummarization = [TextSummarization]::new();

            $title = [Utility]::NormalizeValue($Message.Message.id) + ": " + 
                    [Utility]::NormalizeValue($Message.Message.title);

            $msg = $Message.Message.body.content;
            $description = [regex]::Replace($msg, '(?<=<p>)\\[.+?\\](?=</p>)', '<b>$&</b>');
            $history = [regex]::Replace($msg, '(?<=<p>)\\[.+?\\](?=</p>)', '<b>$&</b>');

            $link = $Message.Message.details | Where-Object Name -eq 'BlogLink'; 
            if ([string]::IsNullOrWhitespace($link))
            {
                $blogLink = "";
            } else { 
                $blogLink = $link.value;
            }

            $link = $Message.Message.details | Where-Object Name -eq 'HelpLink'; 
            if ([string]::IsNullOrWhitespace($link))
            {
                $helpLink = "";
            } else { 
                $helpLink = $link.value;
            }

            $link = $Message.Message.details | Where-Object Name -eq 'ExternalLink'; 
            if ([string]::IsNullOrWhitespace($link))
            {
                $externalLink = "";
            } else { 
                $externalLink = $link.value;
            }

            $summary = $Message.Message.details | Where-Object Name -eq 'Summary'; 
            if ([string]::IsNullOrWhitespace($summary))
            {
                $summary = $null
                try {
                    $summary = $textSummarization.GetSummary($Message.Message.id, [Utility]::ConvertToPlainText($description, $true));
                }
                catch {
                    [TraceLogging]::LogEvent([
                        LoggingLevel]::Error, 
                        "ServiceUpdateEntity", "Summary", "sue371", "Couldn't process communication summary. Details: $_");
                }
            } else {
                $summary = @(
                    [PSCustomObject]@{
                        text = $summary.value
                    }
                )

                $textSummarization.SetSummary($Message.Message.id, [Utility]::ConvertToPlainText($description, $true), $summary);
            }

            $summary = $summary | Select-Object -ExpandProperty text
            $summary = $summary -join " "

            $majorChange = [string]::Empty;
            if ($Message.Message.isMajorChange) { $majorChange = "❗️"; }

            $platforms = $Message.GetPlatforms();

            $tags = @();
            foreach ($service in $Message.Message.services) { $tags += $service };
            foreach ($tag in $Message.Message.tags) { $tags += $tag };
            foreach ($platform in $platforms) { $tags += $platform }
            $tagsJoined = $tags -join ' • ';

            $resources = ""
            $resources += [string]::IsNullOrWhiteSpace($helpLink) ? "" : "* [Help link]($helpLink)"
            $resources += [string]::IsNullOrWhiteSpace($blogLink) ? "" : "* [Blog article]($blogLink)"
            $resources += [string]::IsNullOrWhiteSpace($externalLink) ? "" : "* [External link]($externalLink)"
            
            if ([string]::IsNullOrWhiteSpace($resources))
            {
                $resources = "No additional resources available"
            }

            $releaseState = $Message.GetReleaseState();
            $generalReleaseState = $releaseState | Where-Object Platform -eq "All" | Select-Object -First 1
            $generalReleaseState = $generalReleaseState.Status -eq "FeatureRolloutStatusNotSupported" ? $null : $generalReleaseState

            $releaseStateAllPlatforms = ""
            if ($null -ne $releaseState -and $releaseState.Count -gt 0)
            {
                $rsAddedItemsCount = 0;
                $releaseStateAllPlatforms = '<table style="border:none;border-collapse:collapse;border-color:#ccc;border-spacing:0;">
                <thead>
                  <tr>
                    <th style="font-weight:bold;text-align:left;vertical-align:middle;border-style:solid;border-width:0px;border-bottom:1px solid rgb(232, 232, 232);color:#333;
                    font-family:Arial, sans-serif;font-size:12px;font-weight:bold;overflow:hidden;padding:10px 5px;word-break:normal;">Roadmap Id</th>
                    <th style="font-weight:bold;text-align:left;vertical-align:middle;border-style:solid;border-width:0px;border-bottom:1px solid rgb(232, 232, 232);color:#333;
                    font-family:Arial, sans-serif;font-size:12px;font-weight:bold;overflow:hidden;padding:10px 5px;word-break:normal;">Platform</th>
                    <th style="font-weight:bold;text-align:left;vertical-align:middle;border-style:solid;border-width:0px;border-bottom:1px solid rgb(232, 232, 232);color:#333;
                    font-family:Arial, sans-serif;font-size:12px;font-weight:bold;overflow:hidden;padding:10px 5px;word-break:normal;">Status</th>
                    <th style="font-weight:bold;text-align:left;vertical-align:middle;border-style:solid;border-width:0px;border-bottom:1px solid rgb(232, 232, 232);color:#333;
                    font-family:Arial, sans-serif;font-size:12px;font-weight:bold;overflow:hidden;padding:10px 5px;word-break:normal;">Ring</th>
                    <th style="font-weight:bold;text-align:left;vertical-align:middle;border-style:solid;border-width:0px;border-bottom:1px solid rgb(232, 232, 232);color:#333;
                    font-family:Arial, sans-serif;font-size:12px;font-weight:bold;overflow:hidden;padding:10px 5px;word-break:normal;">Updated</th>
                  </tr>
                </thead>
                <tbody>'
                
                  $td = '<td style="font-weight:bold;text-align:left;vertical-align:middle;border-style:solid;border-width:0px;color:#333;
                  font-family:Arial, sans-serif;font-size:12px;font-weight:normal;overflow:hidden;padding:10px 5px;word-break:normal;">'
                  $tdEnd = '</td>' 

                foreach ($rs in $releaseState) {
                    if ($rs.Status -ne "FeatureRolloutStatusNotSupported")
                    {
                        $releaseStateAllPlatforms += '<tr>'      
                        $releaseStateAllPlatforms += $td + $rs.RoadmapId + $tdEnd;
                        $releaseStateAllPlatforms += $td + $rs.Platform + $tdEnd;
                        $releaseStateAllPlatforms += $td + $rs.Status + $tdEnd;
                        $releaseStateAllPlatforms += $td + $rs.Ring + $tdEnd;
                        $releaseStateAllPlatforms += $td + [Utility]::DateTimeToString($rs.Updated, "d") + $tdEnd;
                        $releaseStateAllPlatforms += '</tr>'
                        $rsAddedItemsCount++
                    }
                }

                $releaseStateAllPlatforms += '</tbody>
                </table>'

                $releaseStateAllPlatforms = $rsAddedItemsCount -eq 0 ? "" : $releaseStateAllPlatforms

            }

            $indexItem = "<p>Summary: $($summary)</p>"
            $indexItem += $description
            $indexItem += "<p>Services: $([Utility]::NormalizeValue($Message.Message.services) -join ', ')</p>"
            $indexItem += "<p>Tags: $($tags -join ', ')</p>"
            $indexItem += "<p>Platforms: $($platforms -join ', ')</p>"
            $indexItem += "<p>Major change: $($Message.Message.isMajorChange)</p>"
            $indexItem += "<p>Release state: $($null -ne $generalReleaseState ? $generalReleaseState.Status : '')</p>"
            $indexItem += "<p>Release state all platforms: $($releaseStateAllPlatforms)</p>"
            $indexItem += "<p>Action required by: $([Utility]::DateTimeToString($Message.Message.actionRequiredByDateTime))</p>"
            $indexItem += "<p>Resources: $($resources)</p>"

            $this.m_properties.Add("OriginalTitle", [Utility]::NormalizeValue($Message.Message.title));
            $this.m_properties.Add("Title", $title);
            $this.m_properties.Add("NotificationTitle", $title);
            $this.m_properties.Add("Description", $description);
            $this.m_properties.Add("Summary", $summary);
            $this.m_properties.Add("History", $history);
            $this.m_properties.Add("Severity", [Utility]::NormalizeValue($Message.Message.severity));
            $this.m_properties.Add("ServicesArray", [Utility]::NormalizeValue($Message.Message.services));
            $this.m_properties.Add("Services", [Utility]::NormalizeValue($Message.Message.services) -join ', ');
            $this.m_properties.Add("TagsArray", $tags);
            $this.m_properties.Add("Tags", $tagsJoined);
            $this.m_properties.Add("OriginalTags", [Utility]::NormalizeValue($Message.Message.tags));
            $this.m_properties.Add("PlatformsArray", $platforms);
            $this.m_properties.Add("Platforms", $($platforms -join ', '));
            $this.m_properties.Add("ADOTags", $($tags -join ';'));
            $this.m_properties.Add("Category", [Utility]::NormalizeValue($Message.Message.category));
            $this.m_properties.Add("MajorChange", [Utility]::ParseBooleanValue($Message.Message.isMajorChange, $false));
            $this.m_properties.Add("StartTime", [Utility]::DateTimeToString($Message.Message.startDateTime));
            $this.m_properties.Add("EndTime", [Utility]::DateTimeToString($Message.Message.endDateTime));
            $this.m_properties.Add("ReleaseState", $($null -ne $generalReleaseState ? $generalReleaseState.Status : ""));
            $this.m_properties.Add("ReleaseStateLastUpdate", $($null -ne $generalReleaseState ? $generalReleaseState.Updated : ""));
            $this.m_properties.Add("ReleaseStateAll", $releaseStateAllPlatforms);
            $this.m_properties.Add("ActionRequiredBy", [Utility]::DateTimeToString($Message.Message.actionRequiredByDateTime));
            $this.m_properties.Add("LastModified", [Utility]::DateTimeToString($Message.Message.lastModifiedDateTime));
            $this.m_properties.Add("HelpLink", $helpLink);
            $this.m_properties.Add("BlogLink", $blogLink);
            $this.m_properties.Add("ExternalLink", $externalLink);
            $this.m_properties.Add("Resources", $resources);
            $this.m_properties.Add("IndexItem", $indexItem);
        }
    }

    [DateTime]GetExpirationTime(
        [BaseMessage]$Message
    )
    {
        $endTimeFromMetadata = $Message.Message.endDateTime;
        $endTime = $null -eq $endTimeFromMetadata ? $null : $([DateTime]$endTimeFromMetadata).AddMonths(2);
        if ($null -eq $endTime)
        {
            return ([BaseEntity]$this).GetExpirationTime($Message);
        } else {
            return $endTime;
        }
    }
}