#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "  Lab 3/4: Windows Server 2022 Core Relay Setup" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

# 1. Install DHCP Role if missing
Write-Host "[INFO] Checking DHCP Server role..." -ForegroundColor Yellow
$dhcpFeature = Get-WindowsFeature -Name DHCP
if (-not $dhcpFeature.Installed) {
    Write-Host "[ACTION] Installing DHCP Server role and management tools..." -ForegroundColor Yellow
    Install-WindowsFeature -Name DHCP -IncludeManagementTools | Out-Null
    Write-Host "[SUCCESS] DHCP Server role installed." -ForegroundColor Green
} else {
    Write-Host "[SUCCESS] DHCP Server role is already installed." -ForegroundColor Green
}

# 2. Identify Interfaces and Configure IP
Write-Host "[INFO] Available Network Adapters:" -ForegroundColor Yellow
Get-NetAdapter | Format-Table Name, InterfaceDescription, Status

$NodeInterface = Read-Host "Enter the Name of the interface facing the NODE (e.g., 'Ethernet 2')"
Write-Host "[ACTION] Configuring Static IP 192.168.99.81/28 on $NodeInterface..." -ForegroundColor Yellow
New-NetIPAddress -InterfaceAlias $NodeInterface -IPAddress 192.168.99.81 -PrefixLength 28 -ErrorAction SilentlyContinue | Out-Null

# 3. Configure DHCP Scope
Write-Host "[ACTION] Configuring DHCP Scope for Node..." -ForegroundColor Yellow
Restart-Service -Name DHCPServer -Force -ErrorAction SilentlyContinue

$scope = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "NodeScope" }
if (-not $scope) {
    Add-DhcpServerv4Scope -Name "NodeScope" `
        -StartRange 192.168.99.82 `
        -EndRange 192.168.99.82 `
        -SubnetMask 255.255.255.240 `
        -State Active | Out-Null
    Write-Host "[SUCCESS] DHCP Scope created." -ForegroundColor Green
}

Set-DhcpServerv4OptionValue -ScopeId 192.168.99.80 `
    -Router 192.168.99.81 `
    -DnsServer 1.1.1.1, 8.8.8.8 -ErrorAction SilentlyContinue | Out-Null

# 4. Enable IP Forwarding (Routing)
Write-Host "[ACTION] Enabling IP Forwarding (Routing)..." -ForegroundColor Yellow
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "IPEnableRouter" -Value 1 -Force
Write-Host "[SUCCESS] IP Forwarding enabled. (A reboot may be required for routing to fully take effect)." -ForegroundColor Green

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "  RELAY SETUP COMPLETE!" -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Cyan