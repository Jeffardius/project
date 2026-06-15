#Requires -RunAsAdministrator

Write-Host "Fixing Gateway NAT and forwarding..."

# 1. Enable IP forwarding on both interfaces (internal and external)
$internalIf = (Get-NetIPAddress -IPAddress "192.168.99.1" -ErrorAction SilentlyContinue).InterfaceAlias
$externalIf = (Get-NetIPAddress -IPAddress "10.0.0.242" -ErrorAction SilentlyContinue).InterfaceAlias

if (-not $internalIf) {
    Write-Host "Internal interface (192.168.99.1) not found. Exiting."
    exit 1
}
if (-not $externalIf) {
    Write-Host "External interface (10.0.0.242) not found. Exiting."
    exit 1
}

Set-NetIPInterface -InterfaceAlias $internalIf -Forwarding Enabled
Set-NetIPInterface -InterfaceAlias $externalIf -Forwarding Enabled

# 2. Remove any existing NAT to avoid conflicts
Get-NetNat | Remove-NetNat -Confirm:$false -ErrorAction SilentlyContinue

# 3. Create NAT for the entire lab subnet (192.168.99.0/24)
New-NetNat -Name "LabNAT" -InternalIPInterfaceAddressPrefix "192.168.99.0/24" -ErrorAction SilentlyContinue

# 4. Ensure RemoteAccess service is running (required for NAT)
Set-Service RemoteAccess -StartupType Automatic
Start-Service RemoteAccess -ErrorAction SilentlyContinue

# 5. Add a persistent default route if missing (Gateway should already have one via its external DHCP)
$defaultRoute = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue
if (-not $defaultRoute) {
    Write-Host "Warning: No default route found on Gateway. Ensure external interface gets DHCP."
}

# 6. Disable firewall temporarily for testing (optional)
netsh advfirewall set allprofiles state off

Write-Host "Configuration complete. Rebooting Gateway in 5 seconds..."
Start-Sleep -Seconds 5
Restart-Computer -Force
