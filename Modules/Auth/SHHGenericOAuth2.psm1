using module .\SHHBaseCredential.psm1

class SHHGenericOAuth2: SHHBaseCredential
{
    SHHGenericOAuth2(
        [string]$ClientId,
        [string]$ClientSecret,
        [string]$TenantId,
        [string]$TokenUrl,
        [string]$Scope
    )
    {
        $this.ClientId = $ClientId;
        $this.ClientSecret = $ClientSecret;
        $this.TenantId = $TenantId;
        $this.TokenUrl = $TokenUrl;
        $this.Scope = $Scope;
    }
}