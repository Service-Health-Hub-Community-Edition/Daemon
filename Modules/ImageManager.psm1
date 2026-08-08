using module .\M365ServiceHealthHubDB.psm1
using module .\Logging.psm1

class Image
{
    [int]$Id
    [string]$Name
    [string]$Type
    [string]$Format
    [string]$Content

    Image(
        [int]$Id,
        [string]$Name,
        [string]$Type,
        [string]$Format,
        [string]$Content
    )
    {
        $this.Id = $Id;
        $this.Name = $Name;
        $this.Type = $Type;
        $this.Format = $Format;
        $this.Content = $Content;
    }
}

class ImageStore
{
    static [M365ServiceHealthHubDB]$mshh_db = [M365ServiceHealthHubDB]::new();

    static [Image] GetImage(
        [string]$Name,
        [string]$Type
    )
    {
        return [ImageStore]::GetImage($Name, $Type, $null)
    }

    static [Image] GetImage(
        [string]$Name,
        [string]$Type,
        [M365ServiceHealthHubDB]$db
    )
    {
        $res = $null -eq $db ? [ImageStore]::mshh_db.GetImage($Name, $Type) : $db.GetImage($Name, $Type);

        if ($null -ne $res)
        {
            return [Image]::new($res.Id, $res.Name, $res.Type, $res.Format, $res.Content);
        } else {
            return $null;
        }
    }

    static [void] AddImage(
        [string]$Name,
        [string]$Type,
        [string]$Format,
        [string]$Content
    )
    {
        [ImageStore]::AddImage($Name, $Type, $Format, $Content, $null)
    }

    static [void] AddImage(
        [string]$Name,
        [string]$Type,
        [string]$Format,
        [string]$Content,
        [M365ServiceHealthHubDB]$db
    )
    {
        if ($null -eq $db)
        {
            [ImageStore]::mshh_db.AddImage($Name, $Type, $Format, $Content);
        }
        else 
        {
            $db.AddImage($Name, $Type, $Format, $Content);
        }
    }

    static [void] AddImage(
        [string]$Name,
        [string]$Type,
        [string]$Url,
        [M365ServiceHealthHubDB]$db
    )
    {
        $Url = $Url.Trim();
        if (!($Url.EndsWith(".png") -or $Url.EndsWith(".jpg") -or $Url.EndsWith(".jpeg") -or $Url.EndsWith(".gif")))
        {
            throw "Image format is not supported. Supported image formats are PNG, JPEG and GIF";
        }

        $extension = $Url.Substring($Url.LastIndexOf("."));
        $format = "";
        switch ($extension)
        {
            ".png" { $format = "image/png" }
            ".gif" { $format = "image/gif" }
            ".jpg" { $format = "image/jpeg" }
            ".jpeg" { $format = "image/jpeg" }
        }

        $response = Invoke-WebRequest $Url;

        $content = "";

        if ($response.BaseResponse.IsSuccessStatusCode)
        {
            $content = [Convert]::ToBase64String($response.Content);

        }

        if ($null -eq $db)
        {
            [ImageStore]::mshh_db.AddImage($Name, $Type, $format, $content);
        }
        else 
        {
            $db.AddImage($Name, $Type, $format, $content);
        }
    }

    static [void] ProcessImageStoreUpdates()
    {
        [ImageStore]::ProcessImageStoreUpdates($null)
    }

    static [void] ProcessImageStoreUpdates([M365ServiceHealthHubDB]$db)
    {
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "ImageStore", "ProcessImageStoreUpdates", "is401", "Entering method ImageStore.ProcessImageStoreUpdates().");

        $db = $null -eq $db ? [ImageStore]::mshh_db : $db
        $imageStoreVersionTimestamp = $db.GetConfigValue("ImageStoreVersionTimestamp")

        if ([string]::IsNullOrWhiteSpace($imageStoreVersionTimestamp))
        {
            $imageStoreVersionTimestamp = [DateTime]::MinValue
        }

        [TraceLogging]::LogEvent([LoggingLevel]::Information, "ImageStore", "ProcessImageStoreUpdates", "is405", "Local image store version: $($imageStoreVersionTimestamp.ToString('o')).");

        $imageStoreUpdates = Invoke-RestMethod https://servicehealthhub.blob.core.windows.net/imagestore/store.json
        $imageStoreUpdates = $imageStoreUpdates | Sort-Object published
        $latestVersion = $imageStoreUpdates | Select-Object -ExpandProperty published -Last 1

        [TraceLogging]::LogEvent([LoggingLevel]::Information, "ImageStore", "ProcessImageStoreUpdates", "is405", "Latest image store version: $($latestVersion.ToString('o')).");

        $latestUpdateTimestamp = $imageStoreVersionTimestamp

        foreach ($update in $imageStoreUpdates)
        {
            if ($update.published -gt $imageStoreVersionTimestamp)
            {
                [TraceLogging]::LogEvent([LoggingLevel]::Information, "ImageStore", "ProcessImageStoreUpdates", "is419", "Processing image store version $($update.published.ToString('o')).");

                foreach ($image in $update.add)
                {
                    [TraceLogging]::LogEvent([LoggingLevel]::Information, "ImageStore", "ProcessImageStoreUpdates", "is423", "Adding image $($image.Name) | $($image.Type) | $($image.Url).");                                 
                    [ImageStore]::AddImage($image.Name, $image.Type, $image.Url, $db)
                }

                $latestUpdateTimestamp = $update.published
            }
        }

        [TraceLogging]::LogEvent([LoggingLevel]::Information, "ImageStore", "ProcessImageStoreUpdates", "is437", "Setting image store version to $($latestUpdateTimestamp.ToString('o')).");  
        $db.SetConfigValue("ImageStoreVersionTimestamp", $latestUpdateTimestamp)

        [TraceLogging]::LogEvent([LoggingLevel]::Information, "ImageStore", "ProcessImageStoreUpdates", "is449", "Exiting method ImageStore.ProcessImageStoreUpdates().");  
    }
}