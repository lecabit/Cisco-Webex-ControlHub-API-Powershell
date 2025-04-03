# Cisco Webex Device List Script
# This script lists all devices from the Webex API

param (
    [switch]$Debug = $false,
    [switch]$AutoExport = $false,
    [switch]$UseImplicitFlow = $false
)

# Add reference to System.Web for URL decoding
Add-Type -AssemblyName System.Web

# Create a global variable to securely store the token
$global:WebexAuthToken = $null

# Display warning if debug mode is enabled
if ($Debug) {
    Write-Host "WARNING: Debug mode is enabled. Your access token will be displayed in plain text." -ForegroundColor Red
    Write-Host "This should only be used for troubleshooting and not in production environments." -ForegroundColor Red
    $confirmation = Read-Host "Are you sure you want to continue? (Y/N) [Y]"
    if ($confirmation -eq "" -or $confirmation -eq "Y" -or $confirmation -eq "y") {
        # Continue with debug mode enabled
    } else {
        Write-Host "Debug mode cancelled. Continuing with normal execution." -ForegroundColor Yellow
        $Debug = $false
    }
}

# Detect operating system using a different approach
$isUnixSystem = ($PSVersionTable.OS -like "*Unix*") -or ($PSVersionTable.OS -like "*Darwin*") -or ($PSVersionTable.OS -like "*Linux*")

# Function to get the documents folder path based on operating system
function Get-DocumentsPath {
    if ($isUnixSystem) {
        return [Environment]::GetFolderPath('Desktop') # On macOS/Unix, use Desktop as fallback
    } else {
        return [Environment]::GetFolderPath('MyDocuments')
    }
}

# Function to open a URL in the default browser based on platform
function Open-InBrowser {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Url
    )
    
    try {
        if ($isUnixSystem) {
            # For macOS/Unix
            if ($IsMacOS -or ($PSVersionTable.OS -like "*Darwin*")) {
                Start-Process "open" -ArgumentList $Url
            } else {
                # For Linux
                Start-Process "xdg-open" -ArgumentList $Url
            }
        } else {
            # For Windows
            Start-Process $Url
        }
        return $true
    } catch {
        Write-Host "Failed to open browser: $_" -ForegroundColor Red
        return $false
    }
}

# Remove PKCE helper functions as they're no longer needed

function Start-LocalListener {
    param(
        [Parameter(Mandatory=$true)]
        [int]$Port,
        
        [Parameter(Mandatory=$true)]
        [string]$Flow,
        
        [Parameter(Mandatory=$false)]
        [string]$ExpectedState = ""
    )
    
    $token = "No token received"

    # Create a simple HTTP listener on the specified port
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add("http://localhost:$Port/")
    $listener.Start()
    
    Write-Host "Waiting for authorization response on port $Port..." -ForegroundColor Yellow
    
    # Get the response when the user is redirected back
    $context = $listener.GetContext()
    $request = $context.Request
    
    # Different parsing based on flow type
    if ($Flow -eq "Implicit") {
        Write-Host "Implicit flow detected. Processing response..." -ForegroundColor Green
        # For implicit flow, token is in the URL fragment which isn't sent to the server
        # We'll send a script back to the browser to extract it and send it via a query parameter
        $response = $context.Response
        $html = @"
<html>
<body>
<h1>Authentication complete!</h1>
<p>Processing authorization response...</p>
<script>
    // Extract the tokens from URL fragment
    var hash = window.location.hash.substring(1);
    console.log("URL Fragment: " + hash);
    
    // Parse the URL fragment manually since URLSearchParams might not work in all browsers
    var params = {};
    hash.split('&').forEach(function(pair) {
        var parts = pair.split('=');
        if (parts.length === 2) {
            params[parts[0]] = decodeURIComponent(parts[1]);
        }
    });
    
    // Look specifically for id_token as documented by Webex
    var token = params['access_token'];
    var state = params['state'];
    var expectedState = "$ExpectedState";
    
    if (state && expectedState && state !== expectedState) {
        document.body.innerHTML += '<p style="color:red">Error: State parameter mismatch. Possible security issue!</p>';
        document.body.innerHTML += '<p>Received state: ' + state + '</p>';
        document.body.innerHTML += '<p>Expected state: ' + expectedState + '</p>';
    } else if (token) {
        // Redirect with token as a query parameter to send it to the server
        window.location.href = '/token?value=' + encodeURIComponent(token);
    } else {
        document.body.innerHTML += '<p style="color:red">Error: No id_token found in URL fragment</p>';
        document.body.innerHTML += '<p>URL fragment: ' + hash + '</p>';
        document.body.innerHTML += '<p>Parsed parameters: ' + JSON.stringify(params) + '</p>';
    }
</script>
</body>
</html>
"@
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($html)
        $response.ContentLength64 = $buffer.Length
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
        $response.OutputStream.Close()
        
        # Wait for the second request with the token in query param
        $context = $listener.GetContext()
        $request = $context.Request
        
        try {
            # Get the full raw URL
            $fullUrl = $request.Url.ToString()
            # Write-Host "Received callback URL: $fullUrl" -ForegroundColor Yellow
            
            # Extract token directly from the query string
            $rawQuery = $request.Url.Query
            # Write-Host "Raw query: $rawQuery" -ForegroundColor Yellow
            
            if ($rawQuery.StartsWith("?")) {
                $rawQuery = $rawQuery.Substring(1)
            }
            
            # Parse the query string manually to handle large tokens
            $queryParams = @{}
            $rawQuery.Split('&') | ForEach-Object {
                $pair = $_.Split('=', 2)
                if ($pair.Length -eq 2) {
                    $queryParams[$pair[0]] = $pair[1]
                }
            }
            
            # Get the token value
            if ($queryParams.ContainsKey("value")) {
                $token = $queryParams["value"]
                # Decode the URL-encoded token
                $token = [System.Web.HttpUtility]::UrlDecode($token)
                # Store the token in a global variable to avoid any issues with passing it between functions
                $global:WebexAuthToken = $token
                # Write-Host "Successfully extracted token (length: $($token.Length))" -ForegroundColor Green
            } else {
                Write-Host "Error: No 'value' parameter found in query: $rawQuery" -ForegroundColor Red
            }
        }
        catch {
            Write-Host "Error extracting token from URL: $_" -ForegroundColor Red
        }
        
        # Send final response to the browser
        $response = $context.Response
        $html = "<html><body><h1>Authentication complete!</h1><p>You can close this window now.</p></body></html>"
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($html)
        $response.ContentLength64 = $buffer.Length
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
        $response.OutputStream.Close()
        
        # Close the listener
        $listener.Stop()
        
        # Return success flag instead of the token (we'll use the global variable)
        return $true
    }
    
    # Close the listener (this is a fallback, should not be reached with the updated code)
    $listener.Stop()
    return $false
}

function Get-WebexTokenWithImplicitFlow {
    $redirectPort = 8080
    $redirectUri = "http://localhost:$redirectPort/"
    $clientId = "Ca2e050cd985088ebf2233916fbe8b122b0a2221d10d7a77643d67aafbbf3b7ca" # Webex Integration Client ID
    
    # Generate random values for state and nonce
    $state = -join ((65..90) + (97..122) | Get-Random -Count 30 | ForEach-Object {[char]$_})
    $nonce = -join ((65..90) + (97..122) | Get-Random -Count 30 | ForEach-Object {[char]$_})
    
    # Generate authorization URL for implicit flow with id_token response type as per documentation
    $authUrl = "https://webexapis.com/v1/authorize" +
               "?client_id=$clientId" +
               "&response_type=token" +
               "&redirect_uri=$([Uri]::EscapeDataString($redirectUri))" + 
               "&scope=openid%20spark-admin%3Adevices_read%20spark%3Adevices_read" + # Include both openid and device read scopes
               "&state=$state" +
               "&nonce=$nonce"
    
    # Debug: Output authorization URL
    if ($Debug) {
        Write-Host "Authorization URL: $authUrl" -ForegroundColor Yellow
        Write-Host "State: $state" -ForegroundColor Yellow
        Write-Host "Nonce: $nonce" -ForegroundColor Yellow
    }
    
    # Open browser for authorization
    Write-Host "Opening browser for Webex authorization..." -ForegroundColor Yellow
    Open-InBrowser -Url $authUrl
    
    # Start local listener to receive the token
    $success = Start-LocalListener -Port $redirectPort -Flow "Implicit" -ExpectedState $state
    
    # Check if we got a valid token from the global variable
    if ($success -and $global:WebexAuthToken) {
        $idToken = $global:WebexAuthToken
        # Write-Host "Successfully obtained ID token (length: $($idToken.Length))" -ForegroundColor Green
        return $idToken
    } else {
        Write-Host "Failed to obtain ID token." -ForegroundColor Red
        return $null
    }
}

# Handle token acquisition with either Implicit Flow or manual input
$accessTokenPlain = $null

if ($UseImplicitFlow) {
    Write-Host "Using Implicit OAuth flow for Webex..." -ForegroundColor Cyan
    $accessTokenPlain = Get-WebexTokenWithImplicitFlow
    
    # Make sure we capture the global variable if the function return has issues
    if ([string]::IsNullOrEmpty($accessTokenPlain) -and $global:WebexAuthToken) {
        $accessTokenPlain = $global:WebexAuthToken
        Write-Host "Using token from global variable instead of function return" -ForegroundColor Yellow
    }
    
    # Debug the result
    # Write-Host "Token obtained: $($accessTokenPlain -ne $null)" -ForegroundColor Yellow
    # if ($accessTokenPlain) {
    #     Write-Host "Token length: $($accessTokenPlain.Length)" -ForegroundColor Yellow
    # }
    
    if ([string]::IsNullOrEmpty($accessTokenPlain)) {
        Write-Host "Implicit flow authentication failed. Falling back to manual token entry." -ForegroundColor Yellow
        # Fall back to manual token entry
        Write-Host "Please enter your Cisco Webex Personal Access Token" -ForegroundColor Cyan
        $accessToken = Read-Host -AsSecureString
        $tokenCredential = New-Object System.Management.Automation.PSCredential("dummy", $accessToken)
        $accessTokenPlain = $tokenCredential.GetNetworkCredential().Password
        $global:WebexAuthToken = $tokenCredential.GetNetworkCredential().Password
    }
} else {
    # Prompt if user needs help with getting a token
    $helpPrompt = Read-Host "Do you need help getting a Webex Personal Access Token? (Y/N) [Y]"
    if ($helpPrompt -eq "" -or $helpPrompt -eq "Y" -or $helpPrompt -eq "y") {
        Write-Output "Opening Webex developer documentation in your browser..."
        $docUrl = "https://developer.webex.com/docs/getting-started"
        if (Open-InBrowser -Url $docUrl) {
            Write-Host "Documentation opened. Please follow the instructions to create your token." -ForegroundColor Green
        }
    }
    
    # Prompt user for access token securely
    Write-Host "Please enter your Cisco Webex Personal Access Token" -ForegroundColor Cyan
    $accessToken = Read-Host -AsSecureString
    $tokenCredential = New-Object System.Management.Automation.PSCredential("dummy", $accessToken)
    $accessTokenPlain = $tokenCredential.GetNetworkCredential().Password
    $global:WebexAuthToken = $tokenCredential.GetNetworkCredential().Password
}

$accessTokenPlain = $global:WebexAuthToken
# Set up request headers
$headers = @{
    'Authorization' = "Bearer $accessTokenPlain" # Use the ID token
    'Content-Type'  = 'application/json'
}

# For debugging - show token information
# Write-Host "Token length: $($accessTokenPlain.Length) characters" -ForegroundColor Green
if ($Debug) {
    Write-Host "FULL TOKEN: $accessTokenPlain" -ForegroundColor Red
} elseif ($accessTokenPlain.Length -gt 10) {
    # Write-Host "First 10 chars: $($accessTokenPlain.Substring(0, 10))..." -ForegroundColor Green
} else {
    Write-Host "WARNING: Token appears too short: $($accessTokenPlain.Length) chars" -ForegroundColor Red
}

# API endpoint URL
$apiUrl = "https://webexapis.com/v1/devices"

try {
    # Make the API request
    Write-Host "Fetching devices from Webex API..." -ForegroundColor Yellow
    Write-Host "API URL: $apiUrl" -ForegroundColor Yellow
    $response = Invoke-RestMethod -Uri $apiUrl -Headers $headers -Method Get
    
    # Check if devices were returned
    if ($response.items -and $response.items.Count -gt 0) {
        Write-Host "`nFound $($response.items.Count) device(s):" -ForegroundColor Green
        
        # Create a collection of device objects with selected properties
        $deviceTable = $response.items | Select-Object @{
            Name = 'Device ID'; 
            Expression = {
                if ($_.id.Length -gt 10) {
                    $_.id.Substring(0, 10) + "..."
                } else {
                    $_.id
                }
            }
        }, @{
            Name = 'Is Connected';
            Expression = {
                if ($_.connectionStatus -eq "connected") {
                    "Yes"
                } else {
                    "No"
                }
            }
        }, @{
            Name = 'Device Name'; 
            Expression = {$_.displayName}
        }, @{
            Name = 'Type'; 
            Expression = {$_.type}
        }, @{
            Name = 'Serial'; 
            Expression = {$_.serial}
        }, @{
            Name = 'Product'; 
            Expression = {$_.product}
        }
        
        # Display the table
        $deviceTable | Format-Table -AutoSize
        
        # Determine if we should export to CSV
        $shouldExport = $false
        
        if ($AutoExport) {
            # Skip prompt if AutoExport is enabled
            $shouldExport = $true
            Write-Host "AutoExport is enabled. Exporting data to CSV automatically." -ForegroundColor Yellow
        } else {
            # Ask if user wants to export to CSV (default Yes)
            $exportChoice = Read-Host -Prompt "`nDo you want to export the full device data to CSV? (Y/N) [Y]"
            # Default to Yes if empty input or Y
            $shouldExport = ($exportChoice -eq "" -or $exportChoice -eq "Y" -or $exportChoice -eq "y")
        }
        
        if ($shouldExport) {
            Write-Host "Preparing CSV export..." -ForegroundColor Yellow
            
            try {
                # Save path for CSV file using cross-platform documents path
                $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
                $documentsPath = Get-DocumentsPath
                $csvPath = Join-Path -Path $documentsPath -ChildPath "WebexDevices-$timestamp.csv"
                
                # Export all device data to CSV
                $response.items | ConvertTo-Csv -NoTypeInformation | Out-File -FilePath $csvPath -Encoding UTF8
                
                Write-Host "Export complete! File saved to: $csvPath" -ForegroundColor Green
            }
            catch {
                Write-Host "Error exporting to CSV: $_" -ForegroundColor Red
            }
        }
    } else {
        Write-Host "`nNo devices found." -ForegroundColor Yellow
    }
}
catch {
    # Error handling
    Write-Host "`nError accessing the Webex API: $_" -ForegroundColor Red
    if ($_.Exception.Response) {
        $statusCode = $_.Exception.Response.StatusCode.Value__
        Write-Host "Status Code: $statusCode" -ForegroundColor Red
        
        if ($statusCode -eq 401) {
            Write-Host "Authentication failed. Please check your access token." -ForegroundColor Red
        }
    }
}
finally {
    # Clean up sensitive data
    $accessTokenPlain = $null
}

Write-Host "`nScript execution completed." -ForegroundColor Cyan
