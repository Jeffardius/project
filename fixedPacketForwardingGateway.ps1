#Requires -RunAsAdministrator

Write-Host "Fixing Gateway NAT and forwarding..."

# ---------- Helper Functions ----------
function Get-InternalInterface {
    # Try to find an interface with a private IP in the typical lab range (192.168.x.x or 10.x.x.x)
    $internalCandidates = Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
        $_.IPAddress -match '^(192\.168\.|10\.|172\.1[6-9]\.|172\.2[0-9]\.|172\.3[0-1]\.)' -and
        $_.InterfaceAlias -notlike '*Loopback*' -and
        $_.PrefixOrigin -ne 'WellKnown'  # exclude APIPA
    }
    
    if ($internalCandidates.Count -eq 0) {
        Write-Host "No private IP interface found automatically."
        return $null
    }
    elseif ($internalCandidates.Count -eq 1) {
        return $internalCandidates[0].InterfaceAlias
    }
    else {
        Write-Host "Multiple private interfaces found. Please select the internal one:"
        for ($i = 0; $i -lt $internalCandidates.Count; $i++) {
            $if = $internalCandidates[$i]
            Write-Host "$($i+1). $($if.InterfaceAlias) - IP: $($if.IPAddress) / $($if.PrefixLength)"
        }
        $choice = Read-Host "Enter number (1-$($internalCandidates.Count))"
        if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $internalCandidates.Count) {
            return $internalCandidates[[int]$choice-1].InterfaceAlias
        }
        Write-Host "Invalid selection."
        return $null
    }
}

function Get-ExternalInterface {
    # External interface is the one with a default gateway (0.0.0.0/0)
    $defaultRoute = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue
    if (-not $defaultRoute) {
        Write-Host "No default gateway found. Cannot auto-detect external interface."
        return $null
    }
    
    $externalIfIndex = $defaultRoute.InterfaceIndex
    $externalIf = Get-NetIPInterface -InterfaceIndex $externalIfIndex -AddressFamily IPv4
    return $externalIf.InterfaceAlias
}

# ---------- Main Logic ----------
# 1. Detect internal interface (or ask user)
$internalIf = Get-InternalInterface
if (-not $internalIf) {
    Write-Host "Could not detect internal interface automatically."
    Write-Host "Available interfaces:"
    Get-NetIPInterface -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notlike '*Loopback*'} | Format-Table InterfaceAlias, IPAddress, InterfaceMetric
    $internalIf = Read-Host "Please enter the exact InterfaceAlias for the INTERNAL (lab) interface"
    if (-not $internalIf) { Write-Host "No interface provided. Exiting."; exit 1 }
}

# 2. Detect external interface (via default route)
$externalIf = Get-ExternalInterface
if (-not $externalIf) {
    Write-Host "Could not detect external interface via default gateway."
    Write-Host "Available interfaces:"
    Get-NetIPInterface -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notlike '*Loopback*'} | Format-Table InterfaceAlias, IPAddress, InterfaceMetric
    $externalIf = Read-Host "Please enter the exact InterfaceAlias for the EXTERNAL (uplink) interface"
    if (-not $externalIf) { Write-Host "No interface provided. Exiting."; exit 1 }
}

Write-Host "Internal interface : $internalIf"
Write-Host "External interface : $externalIf"
$confirm = Read-Host "Is this correct? (Y/N)"
if ($confirm -ne 'Y' -and $confirm -ne 'y') {
    Write-Host "Operation cancelled by user."
    exit 1
}

# 3. Enable IP forwarding on both interfaces
Set-NetIPInterface -InterfaceAlias $internalIf -Forwarding Enabled
Set-NetIPInterface -InterfaceAlias $externalIf -Forwarding Enabled

# 4. Remove any existing NAT to avoid conflicts
Get-NetNat | Remove-NetNat -Confirm:$false -ErrorAction SilentlyContinue

# 5. Determine the internal subnet prefix from the internal interface's IP
$internalIPConfig = Get-NetIPAddress -InterfaceAlias $internalIf -AddressFamily IPv4
$internalIP = $internalIPConfig.IPAddress
$prefixLen = $internalIPConfig.PrefixLength
# Convert IP and prefix length to network prefix (e.g., 192.168.99.0/24)
$network = [System.Net.IPAddress]::new(([System.Net.IPAddress]::Parse($internalIP).GetAddressBytes() | ForEach-Object -Begin { $i=0 } -Process { $_ -band ($prefixLen -ge ($i+1)*8 ? 0xFF : (0xFF -shl (8-($prefixLen % 8)) -band 0xFF)) ; $i++ }))
$internalSubnet = "$($network.IPAddressToString)/$prefixLen"

Write-Host "Creating NAT for subnet: $internalSubnet"
New-NetNat -Name "LabNAT" -InternalIPInterfaceAddressPrefix $internalSubnet -ErrorAction SilentlyContinue

# 6. Ensure RemoteAccess service is running (required for NAT)
Set-Service RemoteAccess -StartupType Automatic
Start-Service RemoteAccess -ErrorAction SilentlyContinue

# 7. Verify default route exists on external interface
$defaultRoute = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -InterfaceAlias $externalIf -ErrorAction SilentlyContinue
if (-not $defaultRoute) {
    Write-Host "Warning: No default route found on external interface ($externalIf). NAT may not work correctly."
} else {
    Write-Host "Default route found via $externalIf - OK"
}

# 8. Disable firewall temporarily for testing (optional)
netsh advfirewall set allprofiles state off

Write-Host "Configuration complete. Rebooting Gateway in 5 seconds..."
Start-Sleep -Seconds 5
Restart-Computer -Force
