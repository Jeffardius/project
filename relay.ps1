#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "  Lab 3/4: Windows Server 2022 Core Relay Setup" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

# ----------------------------------------------
# 1. Identify interfaces (auto-suggest based on order)
# ----------------------------------------------
$adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
if ($adapters.Count -lt 2) {
    Write-Host "[ERROR] Less than 2 network adapters are Up. Please check your VM network settings." -ForegroundColor Red
    exit 1
}

$defaultInternal = $adapters[0].Name   # First adapter -> towards Gateway
$defaultBridged  = $adapters[1].Name   # Second adapter -> towards Node

Write-Host "[INFO] Detected adapters:" -ForegroundColor Yellow
Write-Host "   Adapter 1 (towards Gateway): $defaultInternal" -ForegroundColor Green
Write-Host "   Adapter 2 (towards Node)   : $defaultBridged" -ForegroundColor Green
Write-Host ""

$internalIf = Read-Host "Enter the NAME of the interface facing the GATEWAY (default: $defaultInternal)"
if ([string]::IsNullOrWhiteSpace($internalIf)) { $internalIf = $defaultInternal }

$bridgedIf = Read-Host "Enter the NAME of the interface facing the NODE (default: $defaultBridged)"
if ([string]::IsNullOrWhiteSpace($bridgedIf)) { $bridgedIf = $defaultBridged }

# ----------------------------------------------
# 2. Configure bridged interface static IP: 192.168.99.81/28
# ----------------------------------------------
Write-Host "[ACTION] Setting static IP 192.168.99.81/28 on $bridgedIf ..." -ForegroundColor Yellow
# Remove any existing IP in the 192.168.99.x range from this interface
Get-NetIPAddress -InterfaceAlias $bridgedIf -AddressFamily IPv4 -ErrorAction SilentlyContinue | 
    Where-Object { $_.IPAddress -like "192.168.99.*" } | 
    Remove-NetIPAddress -Confirm:$false
New-NetIPAddress -InterfaceAlias $bridgedIf -IPAddress 192.168.99.81 -PrefixLength 28 -ErrorAction SilentlyContinue | Out-Null

# ----------------------------------------------
# 3. Configure internal interface to obtain IP via DHCP from Gateway
# ----------------------------------------------
Write-Host "[ACTION] Setting $internalIf to DHCP (will get 192.168.99.2 from Gateway)..." -ForegroundColor Yellow
Set-NetIPInterface -InterfaceAlias $internalIf -Dhcp Enabled -ErrorAction SilentlyContinue
# Force renewal of DHCP lease
ipconfig /renew $internalIf | Out-Null

# ----------------------------------------------
# 4. Enable IP forwarding (routing)
# ----------------------------------------------
Write-Host "[ACTION] Enabling IP Forwarding (Routing)..." -ForegroundColor Yellow
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "IPEnableRouter" -Value 1 -Force
Start-Service RemoteAccess -ErrorAction SilentlyContinue

# ----------------------------------------------
# 5. Install & configure DHCP Server for the Node
# ----------------------------------------------
Write-Host "[ACTION] Checking DHCP Server role..." -ForegroundColor Yellow
$dhcpFeature = Get-WindowsFeature -Name DHCP
if (-not $dhcpFeature.Installed) {
    Write-Host "[ACTION] Installing DHCP Server role..." -ForegroundColor Yellow
    Install-WindowsFeature -Name DHCP -IncludeManagementTools | Out-Null
}

Start-Service DHCPServer -ErrorAction SilentlyContinue
Set-Service DHCPServer -StartupType Automatic

# Authorize DHCP server (required even in workgroup)
Add-DhcpServerInDC -DnsName $env:COMPUTERNAME -ErrorAction SilentlyContinue | Out-Null

# Remove old scope if exists, then create new scope for the Node (single IP: 192.168.99.82)
$scopeName = "NodeScope"
$existingScope = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $scopeName }
if ($existingScope) {
    Remove-DhcpServerv4Scope -ScopeId $existingScope.ScopeId -Force -ErrorAction SilentlyContinue
}
Add-DhcpServerv4Scope -Name $scopeName `
    -StartRange 192.168.99.82 `
    -EndRange 192.168.99.82 `
    -SubnetMask 255.255.255.240 `
    -State Active | Out-Null

# Set DHCP options: default gateway = Relay's bridged IP (192.168.99.81), DNS = 1.1.1.1, 8.8.8.8
Set-DhcpServerv4OptionValue -ScopeId 192.168.99.80 `
    -Router 192.168.99.81 `
    -DnsServer 1.1.1.1, 8.8.8.8 -ErrorAction SilentlyContinue | Out-Null

# Ensure firewall allows DHCP traffic (role already adds rules)
Enable-NetFirewallRule -DisplayGroup "DHCP Server" -ErrorAction SilentlyContinue

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "  RELAY SETUP COMPLETE" -ForegroundColor Green
Write-Host "  - Internal interface ($internalIf) should now have 192.168.99.2 (via Gateway DHCP)" -ForegroundColor Green
Write-Host "  - Bridged interface ($bridgedIf) = 192.168.99.81/28" -ForegroundColor Green
Write-Host "  - Node VM will receive 192.168.99.82 via DHCP" -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Cyan
