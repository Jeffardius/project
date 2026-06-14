#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "  Lab 3/4: Windows Server 2022 Core Relay Setup" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

# 1. Identify Interfaces
Write-Host "[INFO] Available Network Adapters:" -ForegroundColor Yellow
Get-NetAdapter | Format-Table Name, InterfaceDescription, Status

$InternalInterface = Read-Host "Enter the Name of the interface facing the GATEWAY (e.g., 'Ethernet')"
$BridgedInterface = Read-Host "Enter the Name of the interface facing the NODE (e.g., 'Ethernet 2')"

# 2. Configure Bridged Interface Static IP
Write-Host "[ACTION] Configuring Static IP 192.168.99.81/28 on $BridgedInterface..." -ForegroundColor Yellow
New-NetIPAddress -InterfaceAlias $BridgedInterface -IPAddress 192.168.99.81 -PrefixLength 28 -ErrorAction SilentlyContinue | Out-Null

# Ensure Internal Interface is set to DHCP (to get .2 from Gateway)
Set-NetIPInterface -InterfaceAlias $InternalInterface -Dhcp Enabled -ErrorAction SilentlyContinue

# 3. Install and Configure DHCP Server
Write-Host "[ACTION] Checking DHCP Server role..." -ForegroundColor Yellow
$dhcpFeature = Get-WindowsFeature -Name DHCP
if (-not $dhcpFeature.Installed) {
    Write-Host "[ACTION] Installing DHCP Server role..." -ForegroundColor Yellow
    Install-WindowsFeature -Name DHCP -IncludeManagementTools | Out-Null
}

Restart-Service -Name DHCPServer -Force -ErrorAction SilentlyContinue

# Authorize DHCP (required even in workgroup for the service to serve IPs)
Add-DhcpServerInDC -DnsName $env:COMPUTERNAME -ErrorAction SilentlyContinue | Out-Null

# Create DHCP Scope for the Node
Write-Host "[ACTION] Configuring DHCP Scope for Node (192.168.99.80/28)..." -ForegroundColor Yellow
$scope = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "NodeScope" }
if (-not $scope) {
    Add-DhcpServerv4Scope -Name "NodeScope" `
        -StartRange 192.168.99.82 `
        -EndRange 192.168.99.82 `
        -SubnetMask 255.255.255.240 `
        -State Active | Out-Null
}

Set-DhcpServerv4OptionValue -ScopeId 192.168.99.80 `
    -Router 192.168.99.81 `
    -DnsServer 1.1.1.1, 8.8.8.8 -ErrorAction SilentlyContinue | Out-Null

# 4. Enable IP Forwarding
Write-Host "[ACTION] Enabling IP Forwarding (Routing)..." -ForegroundColor Yellow
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "IPEnableRouter" -Value 1 -Force
Start-Service RemoteAccess -ErrorAction SilentlyContinue

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "  RELAY SETUP COMPLETE" -ForegroundColor Green
Write-Host "  Node VM should now receive 192.168.99.82 via DHCP" -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Cyan
