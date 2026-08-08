class SHHBaseCredential{
    [Guid]$id
    [string]$name
    [string]$displayName
    [string]$description

    SHHBaseCredential(
        [string]$name,
        [string]$displayName,
        [string]$description
    )
    {
        $this.id = [Guid]::NewGuid()
        $this.name = $name
        $this.displayName = $displayName
        $this.description = $description
    }

    SHHBaseCredential(
        [Guid]$id
    )
    {
        $this.id = $id
        $this.Get();
    }

    [void]Get()
    {
        throw "Not implemented"
    }

    [void]Update()
    {
        throw "Not implemented"
    }

    [void]Authenticate()
    {
        throw "Not implemented"
    }

    [System.Collections.Hashtable]GetAuthorizationHeader()
    {
        throw "Not implemented"
    }
    
    [System.Collections.Hashtable]GetAuthorizationHeader(
        [System.Collections.Hashtable]$existingHeaders
    )
    {
        $authHeader = $this.GetAuthorizationHeader()
        if ($null -ne $existingHeaders)
        {
            foreach ($key in $existingHeaders.Keys)
            {
                if ($key -ne "Authorization")
                {
                    $authHeader.Add($key, $existingHeaders[$key])
                }
            }
        }
        
        return $authHeader
    }
}