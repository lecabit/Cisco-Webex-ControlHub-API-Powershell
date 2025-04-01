# Cisco Webex Device List Script
# This script lists all devices from the Webex API

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

# Prompt user for access token securely
Write-Host "Please enter your Cisco Webex Personal Access Token" -ForegroundColor Cyan
$accessToken = Read-Host -AsSecureString

# Alternative approach to convert SecureString to plain text
$tokenCredential = New-Object System.Management.Automation.PSCredential("dummy", $accessToken)
$accessTokenPlain = $tokenCredential.GetNetworkCredential().Password

# Set up request headers
$headers = @{
    'Authorization' = "Bearer $accessTokenPlain"
    'Content-Type'  = 'application/json'
}

# For debugging - show token length and first few characters
Write-Host "Token length: $($accessTokenPlain.Length) characters" -ForegroundColor Green
if ($accessTokenPlain.Length -gt 10) {
    Write-Host "First 10 chars: $($accessTokenPlain.Substring(0, 10))..." -ForegroundColor Green
} else {
    Write-Host "WARNING: Token appears too short: $($accessTokenPlain.Length) chars" -ForegroundColor Red
}

# API endpoint URL
$apiUrl = "https://webexapis.com/v1/devices"

try {
    # Make the API request
    Write-Host "Fetching devices from Webex API..." -ForegroundColor Yellow
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
                if ($_.isConnected -eq $true) {
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
        
        # Ask if user wants to export to CSV (default Yes)
        $exportChoice = Read-Host -Prompt "`nDo you want to export the full device data to CSV? (Y/N) [Y]"
        # Default to Yes if empty input or Y
        if ($exportChoice -eq "" -or $exportChoice -eq "Y" -or $exportChoice -eq "y") {
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
