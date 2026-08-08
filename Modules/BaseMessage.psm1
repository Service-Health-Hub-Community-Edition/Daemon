enum MessageSource
{
    Database = 0;
    API = 1;
}

class BaseMessage
{
    [string]$Id = [string]::Empty;
    [string]$WorkItemId = [string]::Empty;
    [string]$WorkItemUrl = [string]::Empty;
    [bool]$ExistsInDatabase = $false;
    [System.Object]$Message = $null;
    [string]$MessageJson = [string]::Empty;
    [DateTime]$LastUpdatedTime;
    [bool]$NewItem = $true;
    [bool]$UpdatesAvailable = $true;
    [DateTime]$LastUpdatedTimeFromDB;
    [int]$Indexed = 0;
    [System.Collections.Hashtable]$PropertyBag = [System.Collections.Hashtable]::new();

    BaseMessage()
    {

    }

    Initialize(
        [System.Object]$DatabaseObject
    )
    {
        if ($null -ne $DatabaseObject) {
            $this.ExistsInDatabase = $true;
            $this.Id = $DatabaseObject.ID;
            $this.LastUpdatedTime = $DatabaseObject.LastUpdatedTime;
            $this.MessageJson = $DatabaseObject.Data;
            $this.WorkItemId = $DatabaseObject.WorkItemID;
            $this.WorkItemUrl = $DatabaseObject.WorkItemURL;
            $this.Indexed = [string]::IsNullOrWhiteSpace($DatabaseObject.Indexed) ? 0 : $DatabaseObject.Indexed;
            $this.DeserializeMessage();
        }
        else {
            $this.ExistsInDatabase = $false;
        }
    }

    [void]DeserializeMessage()
    {
        if (![string]::IsNullOrWhiteSpace($this.MessageJson)) {
            $this.Message = ConvertFrom-Json $this.MessageJson;
        }
    }

    [void]Index()
    {

    }
}