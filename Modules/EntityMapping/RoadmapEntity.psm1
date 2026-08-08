using module ..\Utility.psd1
using module ..\Utility.psm1
using module ..\Logging.psm1
using module ..\BaseMessage.psm1
using module .\BaseEntity.psm1

class RoadmapEntity: BaseEntity
{
    RoadmapEntity(
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
            $title = [Utility]::NormalizeValue($Message.Message.id) + ": " + 
                    [Utility]::NormalizeValue($Message.Message.title);

            $description = $Message.Message.Description;
            $history = $Message.Message.Description;

            $lastUpdated = "";
            if (![string]::IsNullOrWhitespace($Message.Message.LastUpdated))
            {
                $lastUpdated = $Message.Message.LastUpdated;
            }

            $published = "";
            if (![string]::IsNullOrWhitespace($Message.Message.Published))
            {
                $published = $Message.Message.Published;
            }

            $indexItem = "<p>$description</p>"
            $indexItem += "<p><b>Last Updated:</b> " + [Utility]::DateTimeToString($lastUpdated) + "</p>";
            $indexItem += "<p><b>Published:</b> " + [Utility]::DateTimeToString($published) + "</p>";
            $indexItem += "<p><b>Tags:</b> " + [Utility]::NormalizeValue($Message.Message.Tags.tagName) -join ', ' + "</p>";
            $indexItem += "<p><b>Products:</b> " + [Utility]::NormalizeValue($Message.Message.Products.tagName) -join ', ' + "</p>";
            $indexItem += "<p><b>Cloud Instances:</b> " + [Utility]::NormalizeValue($Message.Message.CloudInstances.tagName) -join ', ' + "</p>";
            $indexItem += "<p><b>Release Phase:</b> " + [Utility]::NormalizeValue($Message.Message.ReleasePhase.tagName) -join ', ' + "</p>";
            $indexItem += "<p><b>Platforms:</b> " + [Utility]::NormalizeValue($Message.Message.Platforms.tagName) -join ', ' + "</p>";
            $indexItem += "<p><b>Availability:</b> " + [Utility]::DateTimeToString($Message.Message.AvailabilityDate) + "</p>";
            $indexItem += "<p><b>Public Preview:</b> " + [Utility]::DateTimeToString($Message.Message.PublicPreviewDate) + "</p>";
            $indexItem += "<p><b>Published:</b> " + [Utility]::DateTimeToString($Message.Message.Published) + "</p>";

            $this.m_properties.Add("OriginalTitle", [Utility]::NormalizeValue($Message.Message.title));
            $this.m_properties.Add("Title", $title);
            $this.m_properties.Add("NotificationTitle", $title);
            $this.m_properties.Add("Description", $description);
            $this.m_properties.Add("History", $history);
            $this.m_properties.Add("Status", [Utility]::NormalizeValue($Message.Message.Status));
            $this.m_properties.Add("RoadmapUrl", [Utility]::NormalizeValue($Message.Message.Link));
            $this.m_properties.Add("MoreInfoLink", [Utility]::NormalizeValue($Message.Message.MoreInfoLink));
            $this.m_properties.Add("CategoryArray", [Utility]::NormalizeValue($Message.Message.Tags.tagName));
            $this.m_properties.Add("Category", [Utility]::NormalizeValue($Message.Message.Tags.tagName) -join ', ');
            $this.m_properties.Add("CategoryTags", [Utility]::NormalizeValue($Message.Message.Tags.tagName) -join ';');
            $this.m_properties.Add("Products", [Utility]::NormalizeValue($Message.Message.Products.tagName) -join ', ');
            $this.m_properties.Add("ProductsArray", [Utility]::NormalizeValue($Message.Message.Products.tagName));
            $this.m_properties.Add("CloudInstancesArray", [Utility]::NormalizeValue($Message.Message.CloudInstances.tagName));
            $this.m_properties.Add("CloudInstances", [Utility]::NormalizeValue($Message.Message.CloudInstances.tagName) -join ', ');
            $this.m_properties.Add("ReleasePhaseArray", [Utility]::NormalizeValue($Message.Message.ReleasePhase));
            $this.m_properties.Add("ReleasePhase", [Utility]::NormalizeValue($Message.Message.ReleasePhase.tagName) -join ', ');
            $this.m_properties.Add("PlatformsArray", [Utility]::NormalizeValue($Message.Message.Platforms.tagName));
            $this.m_properties.Add("Platforms", [Utility]::NormalizeValue($Message.Message.Platforms.tagName) -join ', ');
            $this.m_properties.Add("Availability", [Utility]::NormalizeValue($Message.Message.AvailabilityDate));
            $this.m_properties.Add("AvailabilityFrom", [Utility]::DateTimeToString($Message.Message.AvailabilityDateFrom));
            $this.m_properties.Add("AvailabilityTo", [Utility]::DateTimeToString($Message.Message.AvailabilityDateTo));
            $this.m_properties.Add("PublicPreview", [Utility]::NormalizeValue($Message.Message.PublicPreviewDate));
            $this.m_properties.Add("PublicPreviewFrom", [Utility]::DateTimeToString($Message.Message.PublicPreviewDateFrom));
            $this.m_properties.Add("PublicPreviewTo", [Utility]::DateTimeToString($Message.Message.PublicPreviewDateTo));
            $this.m_properties.Add("LastModified", $lastUpdated);
            $this.m_properties.Add("LastModifiedString", [Utility]::DateTimeToString($Message.Message.LastUpdated));
            $this.m_properties.Add("Published", $published);
            $this.m_properties.Add("PublishedString", [Utility]::DateTimeToString($Message.Message.Published));
            $this.m_properties.Add("IndexItem", $indexItem);
        }
    }

    [DateTime]GetExpirationTime(
        [BaseMessage]$Message
    )
    {
        $endTimeFromMetadata = $Message.Message.AvailabilityDateTo;
        $endTime = $null -eq $endTimeFromMetadata ? $null : $([DateTime]$endTimeFromMetadata).AddMonths(2);
        if ($null -eq $endTime)
        {
            return ([BaseEntity]$this).GetExpirationTime($Message);
        } else {
            return $endTime;
        }
    }
}