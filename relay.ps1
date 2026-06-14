#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "  Lab 3/4: Windows Server 2022 Core Relay Setup" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

# Hardcoded interface names
$internalIf = "Ethernet"
$bridgedIf  = "Ethernet 2"

# Verify interfaces
$eth1 = Get-NetAdapter -Name $internalIf -ErrorAction SilentlyContinue
$eth2 = Get-NetAdapter -Name $bridgedIf -ErrorAction SilentlyContinue
if (-not $eth1 -or $eth1.Status -ne 'Up') { Write-Host "[ERROR] $internalIf not UP" -ForegroundColor Red; exit 1 }
if (-not $eth2 -or $eth2.Status -ne 'Up') { Write-Host "[ERROR] $bridgedIf not UP" -ForegroundColor Red; exit 1 }

Write-Host "[INFO] Using: Internal=$internalIf, Bridged=$bridgedIf" -ForegroundColor Green

# Configure bridged static IP
$targetIP = "192.168.99.81"
$prefix = 28
$currentBridgedIP = Get-NetIPAddress -InterfaceAlias $bridgedIf -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -eq $targetIP -and $_.PrefixLength -eq $prefix }
if (-not $currentBridgedIP) {
    Write-Host "[ACTION] Setting static IP $targetIP/$prefix on $bridgedIf"
    Get-NetIPAddress -InterfaceAlias $bridgedIf -AddressFamily IPv4 | Where-Object { $_.IPAddress -like "192.168.99.*" } | Remove-NetIPAddress -Confirm:$false
    New-NetIPAddress -InterfaceAlias $bridgedIf -IPAddress $targetIP -PrefixLength $prefix | Out-Null
}

# Internal interface DHCP
$dhcpStatus = Get-NetIPInterface -InterfaceAlias $internalIf | Select-Object -ExpandProperty Dhcp
if ($dhcpStatus -ne 'Enabled') {
    Write-Host "[ACTION] Setting $internalIf to DHCP"
    Set-NetIPInterface -InterfaceAlias $internalIf -Dhcp Enabled
    ipconfig /renew $internalIf | Out-Null
}

# Enable IP forwarding – registry + immediate netsh
Write-Host "[ACTION] Enabling IP forwarding..."
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "IPEnableRouter" -Value 1 -Force
netsh interface ipv4 set interface "$internalIf" forwarding=enabled | Out-Null
netsh interface ipv4 set interface "$bridgedIf" forwarding=enabled | Out-Null

# Install Routing feature if missing
if (-not (Get-WindowsFeature -Name Routing).Installed) {
    Install-WindowsFeature -Name Routing -IncludeManagementTools | Out-Null
}

# Start RemoteAccess service
$ras = Get-Service RemoteAccess -ErrorAction SilentlyContinue
if ($ras.Status -ne 'Running') {
    Set-Service RemoteAccess -StartupType Automatic
    try { Start-Service RemoteAccess -ErrorAction Stop; Write-Host "[INFO] RemoteAccess started." }
    catch { Write-Host "[WARN] RemoteAccess failed – reboot may be needed." -ForegroundColor Yellow }
}

# Firewall rules for routing
Enable-NetFirewallRule -DisplayGroup "Routing and Remote Access" -ErrorAction SilentlyContinue

# Ensure default route (should be 192.168.99.1)
if (-not (Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue)) {
    Write-Host "[ACTION] Adding default route via 192.168.99.1"
    New-NetRoute -DestinationPrefix "0.0.0.0/0" -NextHop "192.168.99.1" -InterfaceAlias $internalIf | Out-Null
}

# DHCP Server setup (unchanged)
$dhcpFeature = Get-WindowsFeature -Name DHCP
if (-not $dhcpFeature.Installed) { Install-WindowsFeature -Name DHCP -IncludeManagementTools | Out-Null }
$dhcpSvc = Get-Service DHCPServer -ErrorAction SilentlyContinue
if ($dhcpSvc.Status -ne 'Running') { Start-Service DHCPServer; Set-Service DHCPServer -StartupType Automatic }

$domainStatus = (Get-CimInstance Win32_ComputerSystem).PartOfDomain
if ($domainStatus) { Add-DhcpServerInDC -DnsName $env:COMPUTERNAME -ErrorAction SilentlyContinue }

$nodeScopeId = "192.168.99.80"
$existingScope = Get-DhcpServerv4Scope -ScopeId $nodeScopeId -ErrorAction SilentlyContinue
if (-not $existingScope) {
    Add-DhcpServerv4Scope -Name "NodeScope" -StartRange 192.168.99.82 -EndRange 192.168.99.82 -SubnetMask 255.255.255.240 -State Active | Out-Null
    Set-DhcpServerv4OptionValue -ScopeId $nodeScopeId -Router 192.168.99.81 -DnsServer @("8.8.8.8","8.8.4.4") -ErrorAction Stop | Out-Null
}
$nodeMAC = "08-00-27-91-C0-11"
if (-not (Get-DhcpServerv4Reservation -IPAddress 192.168.99.82 -ErrorAction SilentlyContinue)) {
    Add-DhcpServerv4Reservation -ScopeId $nodeScopeId -IPAddress 192.168.99.82 -ClientId $nodeMAC -Description "Node VM" | Out-Null
}
Enable-NetFirewallRule -DisplayGroup "DHCP Server" -ErrorAction SilentlyContinue

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "  RELAY SETUP COMPLETE" -ForegroundColor Green
Write-Host "  IP forwarding is now ACTIVE (no reboot required)." -ForegroundColor Green
Write-Host "  Test from Node: ping 192.168.99.1 and ping 8.8.8.8" -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Cyan
