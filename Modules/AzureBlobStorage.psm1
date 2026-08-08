using module .\AuthManager.psm1
using module .\AuthManagerHelper.psm1
using module .\ConfigurationManager.psm1
using module .\Logging.psm1

class AzureBlobStorage
{
    hidden [string]$StorageURI = [string]::Empty;
    hidden [AuthManager] $AuthManager = $null;

    AzureBlobStorage(
       [string]$StorageURI 
    )
    {
        $this.Initialize($([AuthManagerHelper]::CreateInstance("https://storage.azure.com/")), $StorageURI);
    }

    AzureBlobStorage(
       [string]$StorageURI,
       [AuthManager]$AuthManager
    )
    {
        $this.Initialize($AuthManager, $StorageURI);
    }

    hidden [void]Initialize(
        [AuthManager]$AuthManager,
        [string]$StorageURI
    )
    {
        if ([string]::IsNullOrWhiteSpace($StorageURI))
        {
            $errorMessage = "Azure Blob Storage configuration is not found. Please specify StorageURI parameter and try again.";
            [TraceLogging]::LogEvent([LoggingLevel]::Error, "AzureBlobStorage", "Initialization", "abs109", $errorMessage);
            throw $errorMessage;
        } else {
            $this.StorageURI = $StorageURI.TrimEnd("/");
        }

        $this.AuthManager = $AuthManager;
    }

    [System.Object]DownloadFile(
        [string]$Url
    )
    {
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureBlobStorageManager", "Secret", "abs260", "Entering method AzureBlobStorage.DownloadFile()");
        
        $Headers = @{
            Authorization = [string]::Format("{0} {1}",
                $this.AuthManager.Token.token_type,
                $this.AuthManager.Token.access_token);
            'x-ms-version' = '2020-10-02';
        }

        [TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureBlobStorageManager", "Secret", "abs265", "Downloading file $Url");
        $result = Invoke-RestMethod -Uri $Url -Method Get -Headers $headers

        [TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureBlobStorageManager", "Secret", "abs26f", "Exiting method AzureBlobStorage.DownloadFile()");
        
        return $result;
    }

    [string]UploadFile(
        [string]$FileName,
        [System.Object]$Data
    )
    {
        [TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureBlobStorageManager", "Secret", "abs270", "Entering method AzureBlobStorage.UploadFile()");
        
        $uri = [string]::Format("{0}/{1}", $this.StorageURI, $FileName);

        $Headers = @{
            Authorization = [string]::Format("{0} {1}",
                $this.AuthManager.Token.token_type,
                $this.AuthManager.Token.access_token);
            'x-ms-blob-type' = 'BlockBlob';
            'x-ms-version' = '2020-10-02';
            'x-ms-type' = 'file';
            'Content-Type' = 'application/octet-stream';
        }

        [TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureBlobStorageManager", "Secret", "abs275", "Uploading file $FileName to $($this.StorageURI). File size: $($data.Length)");
        Invoke-RestMethod -Uri $uri -Method PUT -Headers $headers -Body $data | Out-Null

        [TraceLogging]::LogEvent([LoggingLevel]::Information, "AzureBlobStorageManager", "Secret", "abs27f", "Exiting method AzureBlobStorage.UploadFile()");
        
        return $uri;
    }
}