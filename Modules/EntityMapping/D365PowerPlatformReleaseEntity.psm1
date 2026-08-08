using module ..\Utility.psd1
using module ..\Utility.psm1
using module ..\Logging.psm1
using module ..\BaseMessage.psm1
using module .\BaseEntity.psm1

class D365PowerPlatformReleaseEntity: BaseEntity
{
    D365PowerPlatformReleaseEntity(
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
            $title = [Utility]::NormalizeValue($Message.Message.FeatureName);

            $msg = $Message.Message.FeatureDetails

            if ($Message.Message.SHHImageMetadata.Count -gt 0)
            {
                foreach ($image in $Message.Message.SHHImageMetadata)
                {
                    $msg += '<br/>'
                    if (![string]::IsNullOrWhiteSpace($image.Thumbnail))
                    {
                        $msg += '<img src="' + $image.Thumbnail + '" />'
                    }

                    if (![string]::IsNullOrWhiteSpace($image.Image))
                    {
                        $msg += '<br/><a href="' + $image.Image + '" target="_blank">' + $image.Description + '</a>'
                    }
                }
            }

            $description = [regex]::Replace($msg, '(?<=<p>)\\[.+?\\](?=</p>)', '<b>$&</b>');
            $history = [regex]::Replace($msg, '(?<=<p>)\\[.+?\\](?=</p>)', '<b>$&</b>');

            $tags = @();
            $tags += [Utility]::NormalizeValue($Message.Message.Product);
            $tags += [Utility]::NormalizeValue($Message.Message.ParentProductName);
            $tags += [Utility]::NormalizeValue($Message.Message.FeatureType);

            $resources = "<ul>"
            if (![string]::IsNullOrWhiteSpace($Message.Message.DocsUrl))
            {
                $resources += "<li><a href=`"$($Message.Message.DocsUrl)`">Documentation</a></li>"
            }
            if (![string]::IsNullOrWhiteSpace($Message.Message.BlogURL))
            {
                $resources += "<li><a href=`"$($Message.Message.BlogURL)`">Blog article</a></li>"
            }
            if (![string]::IsNullOrWhiteSpace($Message.Message.OverviewVideo))
            {
                $resources += "<li><a href=`"$($Message.Message.OverviewVideo)`">Overview video</a></li>"
            }
            $resources += "</ul>"

            $indexItem = "<p>$description</p>"
            $indexItem += "<p><b>Business value:</b> " + [Utility]::NormalizeValue($Message.Message.BusinessValue) + "</p>";
            $indexItem += "<p><b>Tags:</b> " + [Utility]::NormalizeValue($tags) -join ', ' + "</p>";
            $indexItem += "<p><b>Product:</b> " + [Utility]::NormalizeValue($Message.Message.Product) + "</p>";
            $indexItem += "<p><b>Product Area:</b> " + [Utility]::NormalizeValue($Message.Message.ProductArea) + "</p>";
            $indexItem += "<p><b>Parent Product:</b> " + [Utility]::NormalizeValue($Message.Message.ParentProductName) + "</p>";
            $indexItem += "<p><b>Feature Type:</b> " + [Utility]::NormalizeValue($Message.Message.FeatureType) + "</p>";
            $indexItem += "<p><b>Release Wave:</b> " + [Utility]::NormalizeValue($Message.Message.ReleaseWaveName) + "</p>";
            $indexItem += "<p><b>Release Wave Start Ship Date:</b> " + [Utility]::DateTimeToString($Message.Message.RW_StartShipDate) + "</p>";
            $indexItem += "<p><b>Release Wave End Ship Date:</b> " + [Utility]::DateTimeToString($Message.Message.RW_EndShipDate) + "</p>";
            $indexItem += "<p><b>GA Date:</b> " + [Utility]::DateTimeToString($Message.Message.GADate, "o", "MM/dd/yyyy") + "</p>";
            $indexItem += "<p><b>GA Status:</b> " + [Utility]::NormalizeValue($Message.Message.GAStatus) + "</p>";
            $indexItem += "<p><b>Early Access Date:</b> " + [Utility]::DateTimeToString($Message.Message.EarlyAccessDate, "o", "MM/dd/yyyy") + "</p>";
            $indexItem += "<p><b>Early Access Status:</b> " + [Utility]::NormalizeValue($Message.Message.EAStatus) + "</p>";
            $indexItem += "<p><b>Public Preview Date:</b> " + [Utility]::DateTimeToString($Message.Message.PublicPreviewDate, "o", "MM/dd/yyyy") + "</p>";
            $indexItem += "<p><b>Public Preview Status:</b> " + [Utility]::NormalizeValue($Message.Message.PPStatus) + "</p>";

            $this.m_properties.Add("Title", $title);
            $this.m_properties.Add("NotificationTitle", $title);
            $this.m_properties.Add("Description", $description);
            $this.m_properties.Add("History", $history);
            $this.m_properties.Add("BusinessValue", [Utility]::NormalizeValue($Message.Message.BusinessValue));
            $this.m_properties.Add("FeatureType", [Utility]::NormalizeValue($Message.Message.FeatureType));
            $this.m_properties.Add("Product", [Utility]::NormalizeValue($Message.Message.Product));
            $this.m_properties.Add("ProductArea", [Utility]::NormalizeValue($Message.Message.ProductArea));
            $this.m_properties.Add("ParentProduct", [Utility]::NormalizeValue($Message.Message.ParentProductName));
            $this.m_properties.Add("EnabledFor", [Utility]::NormalizeValue($Message.Message.EnabledFor));
            $this.m_properties.Add("ReleaseWaveId", [Utility]::NormalizeValue($Message.Message.ReleaseWaveId));
            $this.m_properties.Add("ReleaseWave", [Utility]::NormalizeValue($Message.Message.ReleaseWaveName));
            $this.m_properties.Add("RWStartShipDate", [Utility]::DateTimeToString($Message.Message.RW_StartShipDate));
            $this.m_properties.Add("RWEndShipDate", [Utility]::DateTimeToString($Message.Message.RW_EndShipDate));
            $this.m_properties.Add("RW_Status", [Utility]::NormalizeValue($Message.Message.RW_Status));
            $this.m_properties.Add("EarlyAccessDate", [Utility]::DateTimeToString($Message.Message.EarlyAccessDate, "o", "MM/dd/yyyy"));
            $this.m_properties.Add("EarlyAccessStatus", [Utility]::NormalizeValue($Message.Message.EAStatus));
            $this.m_properties.Add("PublicPreviewDate", [Utility]::DateTimeToString($Message.Message.PublicPreviewDate, "o", "MM/dd/yyyy"));
            $this.m_properties.Add("PublicPreviewStatus", [Utility]::NormalizeValue($Message.Message.PPStatus));
            $this.m_properties.Add("GADate", [Utility]::DateTimeToString($Message.Message.GADate, "o", "MM/dd/yyyy"));
            $this.m_properties.Add("GAStatus", [Utility]::NormalizeValue($Message.Message.GAStatus));
            $this.m_properties.Add("Documentation", [Utility]::NormalizeValue($Message.Message.DocsUrl));
            $this.m_properties.Add("BlogArticle", [Utility]::NormalizeValue($Message.Message.BlogURL));
            $this.m_properties.Add("OverviewVideo", [Utility]::NormalizeValue($Message.Message.OverviewVideo));
            $this.m_properties.Add("ResourcesHtml", $resources);
            $this.m_properties.Add("TagsArray", [Utility]::NormalizeValue($tags));
            $this.m_properties.Add("Tags", [Utility]::NormalizeValue($tags) -join ', ');
            $this.m_properties.Add("Published", [Utility]::DateTimeToString($Message.Message.FirstGitHubPushDate, "o", "MM/dd/yyyy"));
            $this.m_properties.Add("LastUpdate", [Utility]::DateTimeToString($Message.Message.GitCommitDate, "o", "MM/dd/yyyy"));
            $this.m_properties.Add("IndexItem", $indexItem);
        }
    }

    [DateTime]GetExpirationTime(
        [BaseMessage]$Message
    )
    {
        $endTimeFromMetadata = $Message.Message.GADate;
        $endTime = [string]::IsNullOrWhiteSpace($endTimeFromMetadata) ? $null : $([DateTime]$endTimeFromMetadata).AddMonths(2);
        if ($null -eq $endTime)
        {
            return ([BaseEntity]$this).GetExpirationTime($Message);
        } else {
            return $endTime;
        }
    }
}