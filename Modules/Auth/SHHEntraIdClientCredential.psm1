<#
.SYNOPSIS
This module provides a class for managing authentication tokens using Azure AD.

.DESCRIPTION
The AuthManager module includes methods for retrieving, refreshing, and decoding tokens, 
as well as checking if managed identity authentication is used.

.AUTHOR
Aleksandar Draskovic, Microsoft Deutschland GmbH

.DATE
2025-03-13

.VERSION
2.0.2503.0
#>

using module .\SHHBaseCredential.psm1
using module ..\ConfigurationManager.psm1
using module ..\M365ServiceHealthHubDB.psm1
using module ..\Utility.psd1
using module ..\Utility.psm1
using module ..\Logging.psm1

class SHHEntraIdClientCredential: SHHBaseCredential
{
	hidden [string]$ClientId = [string]::Empty;
	hidden [string]$ClientSecret = [string]::Empty;
	hidden [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate = $null;
	hidden [string]$TenantDomain = [string]::Empty;
	hidden [string]$Resource = [string]::Empty;
	[System.Object]$Token = $null;

	SHHEntraIdClientCredential(
		[string]$ClientId,
		[string]$ClientSecret,
		[string]$TenantDomain,
		[string]$Resource
	)
	{
		$this.id = [Guid]::NewGuid()
		$this.ClientId = $ClientId;
		$this.ClientSecret = $ClientSecret;
		$this.TenantDomain = $TenantDomain;
		$this.Resource = $Resource;
		$this.Token = $this.RetrieveAuthToken($Resource);
	}

	SHHEntraIdClientCredential(
		[string]$ClientId,
		[System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
		[string]$TenantDomain,
		[string]$Resource
	)
	{
		$this.id = [Guid]::NewGuid()
		$this.ClientId = $ClientId;
		$this.Certificate = $Certificate;
		$this.TenantDomain = $TenantDomain;
		$this.Resource = $Resource;
		$this.Token = $this.RetrieveAuthToken($Resource);
	}

	SHHEntraIdClientCredential(
		[string]$Resource
	)
	{
		$this.id = [Guid]::NewGuid()
		$this.Resource = $Resource;
		$this.Token = $this.RetrieveAuthToken($Resource);
	}

	[void]Get()
    {
        $dbObject = $this.m_db.GetCredential($this.id)
        if ($null -eq $dbObject)
        {
            throw "Credential with ID $($this.id) not found in the database."
        }
        $this.name = $dbObject.name
        $this.displayName = $dbObject.displayName
        $this.description = $dbObject.description
		$obj = $(ConvertFrom-Json $dbObject.SerializedObject -Depth 10)
		$this.ClientId = $obj.ClientId

		if ($obj.CertBasedAuth -eq $true)
		{
			try {
				$this.Certificate = [ConfigurationManager]::GetCertificate(("credCert-$($this.id)")
			} catch {
				[TraceLogging]::LogEvent([LoggingLevel]::Error, "SHHEntraIdClientCredential", "Get", "au2881", "Failed to retrieve client secret for credential ID $($this.id). Ensure the secret exists in the Key Vault.");
				throw "Failed to retrieve client secret for credential ID $($this.id). Ensure the secret exists in the Key Vault.";
				$this.Certificate = $null;
			}
		} else {
			try {
				$this.ClientSecret = [ConfigurationManager]::GetSecret("credSecret-$($this.id)")
			} catch {
				[TraceLogging]::LogEvent([LoggingLevel]::Error, "SHHEntraIdClientCredential", "Get", "au2882", "Failed to retrieve client secret for credential ID $($this.id). Ensure the secret exists in the Key Vault.");
				throw "Failed to retrieve client secret for credential ID $($this.id). Ensure the secret exists in the Key Vault.";
				$this.ClientSecret = [string]::Empty;
			}
		}	
		
		$this.TenantDomain = $obj.TenantDomain
		$this.Resource = $obj.Resource
    }

    [void]Update()
    {
        $obj = @{
			ClientId = $this.ClientId;
			CertBasedAuth = $null -ne $this.Certificate;
			TenantDomain = $this.TenantDomain;
			Resource = $this.Resource
		}

		if ($null -ne $this.Certificate)
		{
			$serializedObject = ConvertTo-Json -InputObject $obj -Depth 10
			$this.m_db.SetCredential($this.id, $this.name, $this.GetType().Name, $this.description, $serializedObject);
			[ConfigurationManager]::SetCertificate(("credCert-$($this.id)"), $this.Certificate);
			[ConfigurationManager]::RemoveSecret(("credSecret-$($this.id)"), $this.Certificate);
		}
		else
		{
			$serializedObject = ConvertTo-Json -InputObject $obj -Depth 10
			$this.m_db.SetCredential($this.id, $this.name, $this.displayName, $this.description, $serializedObject);
			[ConfigurationManager]::SetSecret("credSecret-$($this.id)", $this.ClientSecret);
			[ConfigurationManager]::RemoveCertificate(("credCert-$($this.id)"), $this.Certificate);
		}
    }

    [void]Authenticate()
    {
        $this.GetAuthToken() | Out-Null;
		[TraceLogging]::LogEvent([LoggingLevel]::Information, "AuthManager", "Authenticate", "au2880", "Authentication completed successfully.");
    }

    [System.Collections.Hashtable]GetAuthorizationHeader()
    {
		$res = [System.Collections.Hashtable]::new();
	
        $authToken = $this.GetAuthToken();
		if ($null -eq $authToken)
		{
			throw "Authentication token is not available. Please authenticate first.";
		}

		$res.Add("Authorization", $this.GetAuthToken().token_type + " " + $this.GetAuthToken().access_token);
		return $res;
    }

	[System.Object]GetAuthToken()
	{
		if (($null -eq $this.Token) -or ([Utility]::ConvertFromUnixDate($this.Token.expires_on) -le [DateTime]::UtcNow))
		{
			[TraceLogging]::LogEvent([LoggingLevel]::Information, "AuthManager", "AuthToken", "au2881", "Auth. token expired. Retrieving new token.");
			$this.Token = $this.RetrieveAuthToken($this.Resource);
		}
		return $this.Token
	}

	[void]RefreshToken()
	{
		$this.Token = $this.RetrieveAuthToken($this.Resource);
	}

	hidden [string]NormalizeBase64TokenData([string]$Data)
	{
		$Data = $Data.Replace('-', '+').Replace('_', '/')
		switch ($Data.Length % 4) {
			0 {break}
			2 {$Data += '=='}
			3 {$Data += '='}
		}		
		return $Data
	}

	[object]DecodeToken()
	{
		$decodedToken = New-Object -TypeName PSObject
		$header = $this.NormalizeBase64TokenData($this.Token.access_token.Split('.')[0])
		$payload = $this.NormalizeBase64TokenData($this.Token.access_token.Split('.')[1])

		Add-Member `
			-InputObject $decodedToken `
			-NotePropertyName 'Header' `
			-NotePropertyValue $([System.Text.Encoding]::UTF8.GetString([convert]::FromBase64String($header)) | ConvertFrom-Json)

		Add-Member `
			-InputObject $decodedToken `
			-NotePropertyName 'Payload' `
			-NotePropertyValue $([System.Text.Encoding]::UTF8.GetString([convert]::FromBase64String($payload)) | ConvertFrom-Json)

		return $decodedToken
	}

	hidden [System.Boolean]IsMSIAuth()
	{
		if ([string]::IsNullOrWhiteSpace($this.ClientId))
		{
			if ([string]::IsNullOrWhiteSpace($env:IDENTITY_ENDPOINT)){
				throw "ClientId is not set and managed identity is not available. Cannot determine auth method.";
			} else {
				return $true;
			}
		} else {
			return $false;
		}
	}

	hidden [System.String]GetClientAssertion()
	{
		$clientAssertion = $null;
		if ($null -ne $this.Certificate)
		{
			# Create the JWT header
			$header = @{
				alg = "RS256"
				typ = "JWT"
				x5t = [System.Convert]::ToBase64String($this.Certificate.GetCertHash())
			}

			# Create the JWT payload
			$now = [System.DateTime]::UtcNow
			$exp = $now.AddMinutes(10)
			$payload = @{
				aud = "https://login.microsoftonline.com/$($this.TenantDomain)/oauth2/v2.0/token"
				iss = $this.ClientId
				sub = $this.ClientId
				jti = [System.Guid]::NewGuid().ToString()
				nbf = [System.Convert]::ToInt32(($now - [System.DateTime]::UnixEpoch).TotalSeconds)
				exp = [System.Convert]::ToInt32(($exp - [System.DateTime]::UnixEpoch).TotalSeconds)
			}

			# Convert header and payload to JSON
			$headerJson = $header | ConvertTo-Json -Compress
			$payloadJson = $payload | ConvertTo-Json -Compress

			# Base64Url encode the header and payload
			$headerEncoded = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($headerJson)).Replace('+', '-').Replace('/', '_').Replace('=', '')
			$payloadEncoded = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($payloadJson)).Replace('+', '-').Replace('/', '_').Replace('=', '')

			# Create the unsigned token
			$unsignedToken = "$headerEncoded.$payloadEncoded"
			# Sign the token using the certificate
			$sha256 = New-Object System.Security.Cryptography.SHA256CryptoServiceProvider
			$hash = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($unsignedToken))

			$signature = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($this.Certificate).SignHash($hash, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
			$signatureEncoded = [System.Convert]::ToBase64String($signature).Replace('+', '-').Replace('/', '_').Replace('=', '')

			# Create the signed token
			$clientAssertion = "$unsignedToken.$signatureEncoded"
		}

		return $clientAssertion;
	}

	hidden [System.Object]GetTokenRequestBody(
		[string]$Resource
	)
	{
		$body = $null;
		if ($null -eq $this.Certificate)
		{
			$body = @{
				grant_type="client_credentials";
				scope=$Resource+"/.default";
				client_id=$this.ClientId;
				client_secret=$this.ClientSecret
			}
		}
		else
		{
			$body = @{
				grant_type="client_credentials";
				scope=$Resource+"/.default";
				client_assertion=$this.GetClientAssertion();
				client_assertion_type="urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
			}
		}
		
		return $body;
	}

	hidden [System.String]GetTokenRequestUri()
	{
		$uri = $this.IsMSIAuth() ? $env:IDENTITY_ENDPOINT + "?resource=$($this.Resource)&api-version=2019-08-01" : 
								   "https://login.microsoftonline.com/$($this.TenantDomain)/oauth2/v2.0/token"
		return $uri;
	}

	hidden [System.Object]GetTokenRequestHeaders()
	{
		$headers = $this.IsMSIAuth() ? @{"X-IDENTITY-HEADER"="$env:IDENTITY_HEADER"} : 
									   @{ContentType="application/x-www-form-urlencoded"}
		return $headers;
	}

	hidden [System.String]GetTokenRequestMethod()
	{
		$method = $this.IsMSIAuth() ? "GET" : "POST";
		return $method;
	}
	
	hidden [System.Object]RetrieveAuthToken(
		[string]$Resource
	)
	{
		$maxRetries = 10;
		$success = $false;
		$retry = 0;
		$result = $null;

		while ($success -eq $false -and $retry -lt $maxRetries)
		{
			[TraceLogging]::LogEvent([LoggingLevel]::Information, "AuthManager", "AuthToken", "au2910", "Retrieving auth. token. Attempt #$($retry+1) of $maxRetries");
			try {
				$method = $this.GetTokenRequestMethod();
				$uri = $this.GetTokenRequestUri();
				$headers = $this.GetTokenRequestHeaders();

				if ($method -eq "GET")
				{
					$result = Invoke-RestMethod -Method $method -Uri $uri -Headers $headers;
					[TraceLogging]::LogEvent([LoggingLevel]::Information, "AuthManager", "AuthToken", "au2912a", "Auth. token retrieved successfully.");
					$success = $true;
				}
				elseif ($method -eq "POST")
				{
					$body = $this.GetTokenRequestBody($Resource);
					$result = Invoke-RestMethod -Method $method -Uri $uri -Headers $headers -Body $body;
					[TraceLogging]::LogEvent([LoggingLevel]::Information, "AuthManager", "AuthToken", "au2912b", "Auth. token retrieved successfully.");
					$success = $true;
				}
			}
			catch {
				[TraceLogging]::LogEvent([LoggingLevel]::Error, "AuthManager", "AuthToken", "au2913", "Failed to retrieve auth. token. Error: $_");
				$retry++;	
			}
		}

		return $result;
	}
}
