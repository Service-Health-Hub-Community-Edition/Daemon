using module ..\Utility.psd1
using module ..\Utility.psm1
using module ..\Logging.psm1
using module ..\BaseMessage.psm1
using module .\BaseEntity.psm1

class AzureUpdateEntity: BaseEntity
{
    AzureUpdateEntity(
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
            $title = [Utility]::NormalizeValue($Message.Message.title);

            $msg = "";

            foreach ($content in $Message.Message.contents) 
            {
                $msg += "<p>"+$content+"</p>" 
            }

            $description = [regex]::Replace($msg, '(?<=<p>)\\[.+?\\](?=</p>)', '<b>$&</b>');
            $history = [regex]::Replace($msg, '(?<=<p>)\\[.+?\\](?=</p>)', '<b>$&</b>');

            $serviceList = $Message.Message.serviceList
            $serviceListHtml = ""
            if ($null -ne $serviceList -and $serviceList.Count -gt 0)
            {
                $slAddedItemsCount = 0;
                $serviceListHtml = '<table style="border:none;border-collapse:collapse;border-color:#ccc;border-spacing:0;">
                <thead>
                  <tr>
                    <th style="font-weight:bold;text-align:left;vertical-align:middle;border-style:solid;border-width:0px;border-bottom:1px solid rgb(232, 232, 232);color:#333;
                    font-family:Arial, sans-serif;font-size:12px;font-weight:bold;overflow:hidden;padding:10px 5px;word-break:normal;">Subscription Id</th>
                    <th style="font-weight:bold;text-align:left;vertical-align:middle;border-style:solid;border-width:0px;border-bottom:1px solid rgb(232, 232, 232);color:#333;
                    font-family:Arial, sans-serif;font-size:12px;font-weight:bold;overflow:hidden;padding:10px 5px;word-break:normal;">Resource group</th>
                    <th style="font-weight:bold;text-align:left;vertical-align:middle;border-style:solid;border-width:0px;border-bottom:1px solid rgb(232, 232, 232);color:#333;
                    font-family:Arial, sans-serif;font-size:12px;font-weight:bold;overflow:hidden;padding:10px 5px;word-break:normal;">Type</th>
                    <th style="font-weight:bold;text-align:left;vertical-align:middle;border-style:solid;border-width:0px;border-bottom:1px solid rgb(232, 232, 232);color:#333;
                    font-family:Arial, sans-serif;font-size:12px;font-weight:bold;overflow:hidden;padding:10px 5px;word-break:normal;">Location</th>
                    <th style="font-weight:bold;text-align:left;vertical-align:middle;border-style:solid;border-width:0px;border-bottom:1px solid rgb(232, 232, 232);color:#333;
                    font-family:Arial, sans-serif;font-size:12px;font-weight:bold;overflow:hidden;padding:10px 5px;word-break:normal;">Id</th>
                  </tr>
                </thead>
                <tbody>'
                
                  $td = '<td style="font-weight:bold;text-align:left;vertical-align:middle;border-style:solid;border-width:0px;color:#333;
                  font-family:Arial, sans-serif;font-size:12px;font-weight:normal;overflow:hidden;padding:10px 5px;word-break:normal;">'
                  $tdEnd = '</td>' 

                foreach ($svc in $serviceList) {
                    $serviceListHtml += '<tr>'      
                    $serviceListHtml += $td + $svc.subscriptionId + $tdEnd;
                    $serviceListHtml += $td + $svc.resourceGroup + $tdEnd;
                    $serviceListHtml += $td + $svc.type + $tdEnd;
                    $serviceListHtml += $td + $svc.location + $tdEnd;
                    $serviceListHtml += $td + $svc.id + $tdEnd;
                    $serviceListHtml += '</tr>'
                    $slAddedItemsCount++
                }

                $serviceListHtml += '</tbody>
                </table>'

                $serviceListHtml = $slAddedItemsCount -eq 0 ? "" : $serviceListHtml

            }

            $this.m_properties.Add("Title", $title);
            $this.m_properties.Add("NotificationTitle", $title);
            $this.m_properties.Add("Description", $description);
            $this.m_properties.Add("History", $history);
            $this.m_properties.Add("Summary", [Utility]::NormalizeValue($Message.Message.summary));
            $this.m_properties.Add("ReleaseStatus", [Utility]::NormalizeValue($Message.Message.releaseStatus));
            $this.m_properties.Add("Article", [Utility]::NormalizeValue($Message.Message.link));
            $this.m_properties.Add("ArticleMarkdownLink", [string]::IsNullOrWhiteSpace($Message.Message.link) ? "None" : "[Link]($([Utility]::NormalizeValue($Message.Message.link)))");
            $this.m_properties.Add("TagsArray", [Utility]::NormalizeValue($Message.Message.tags));
            $this.m_properties.Add("Tags", [Utility]::NormalizeValue($Message.Message.tags) -join ', ');
            $this.m_properties.Add("Published", [Utility]::DateTimeToString($Message.Message.published));
            $this.m_properties.Add("ServiceListHtml", $serviceListHtml);
        }
    }
}