# Cisco Webex Utils

A collection of PowerShell utilities for working with Cisco Webex APIs.

## Get-Devices.ps1

This script retrieves and lists all devices registered with your Cisco Webex account using the Webex API.

### Features

- Lists all Webex devices with key information displayed in a table
- Supports authentication via Personal Access Token or OAuth Implicit Flow
- Cross-platform compatibility (Windows, macOS, Linux)
- Option to export device data to CSV
- Option for automatic CSV export (helpful for scheduled tasks)
- Debug mode for troubleshooting

### Prerequisites

- PowerShell 5.1 or higher (PowerShell Core 6+ recommended for cross-platform usage)
- Internet connection to access Webex APIs
- A Cisco Webex account with appropriate permissions
- Either a Personal Access Token or an OAuth integration in Webex

### Download the script
```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/lecabit/Cisco-Webex-ControlHub-API-Powershell/main/Get-Devices.ps1" -OutFile "Get-Devices.ps1"
```

### Usage

```powershell
# Basic usage with manual token entry
./Get-Devices.ps1

# Use OAuth implicit flow for authentication
./Get-Devices.ps1 -UseImplicitFlow

# Automatically export to CSV without prompting
./Get-Devices.ps1 -AutoExport

# Enable debugging info
./Get-Devices.ps1 -Debug

# Combine options
./Get-Devices.ps1 -UseImplicitFlow -AutoExport
```

### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `-UseImplicitFlow` | Switch | Use OAuth implicit flow for authentication instead of manual token entry |
| `-AutoExport` | Switch | Automatically export results to CSV without prompting |
| `-Debug` | Switch | Enable debugging information (includes sensitive token information) |

### Authentication Methods

#### Personal Access Token

By default, the script will prompt you for a Personal Access Token. You can generate one from the [Webex Developer Portal](https://developer.webex.com/docs/getting-started).

#### OAuth Implicit Flow

When using the `-UseImplicitFlow` parameter, the script will:

1. Open your default browser to authenticate with Webex
2. You'll need to authorize the application
3. After successful authorization, you'll be redirected to a local web server 
4. The script will extract the authentication token and use it automatically

To use OAuth Implicit Flow, you need to create an integration in the Webex Developer Portal:

1. Go to https://developer.webex.com
2. Sign in to your Webex account
3. Navigate to "My Webex Apps"
4. Click "Create a New App"
5. Select "Integration" as the app type
6. Fill in required information
   - Redirect URI: `http://localhost:8080/`
   - Scopes: `spark:devices_read`, `spark-admin:devices_read` and `openid`
7. Update the client ID in the script with your integration's client ID

### Examples

**Basic usage:**
```powershell
./Get-Devices.ps1
```

**Use OAuth and export to CSV automatically:**
```powershell
./Get-Devices.ps1 -UseImplicitFlow -AutoExport
```

### Troubleshooting

- **Authentication failures**: Ensure your token or OAuth client ID is correct.
- **No devices found**: Verify you have the appropriate permissions for your account.
- **Browser issues**: If the browser doesn't open automatically, manually visit the authorization URL shown in the console.
- **Debug mode**: Use the `-Debug` parameter to see more detailed information about what's happening.

### License

This project is available under the MIT License. See LICENSE file for details.
