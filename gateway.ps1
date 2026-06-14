#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "  Lab 4: Windows Server 2022 Core Gateway Setup" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

# ----------------------------------------------
# 1. Install & configure OpenSSH Server (optional but convenient)
# ----------------------------------------------
Write-Host "[INFO] Checking OpenSSH Server capability..." -ForegroundColor Yellow
$sshCapability = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'
if ($sshCapability.State -ne 'Installed') {
    Write-Host "[ACTION] Installing OpenSSH Server..." -ForegroundColor Yellow
    Add-WindowsCapability -Online -Name $sshCapability.Name | Out-Null
}

Write-Host "[ACTION] Configuring SSH for password authentication..." -ForegroundColor Yellow
Start-Service sshd -ErrorAction SilentlyContinue
Set-Service -Name sshd -StartupType Automatic
$sshdConfigPath = "$env:ProgramData\ssh\sshd_config"
if (Test-Path $sshdConfigPath) {
    $content = Get-Content $sshdConfigPath
    $content = $content -replace '#PasswordAuthentication yes', 'PasswordAuthentication yes'
    $content = $content -replace 'PasswordAuthentication no', 'PasswordAuthentication yes'
    Set-Content $sshdConfigPath $content
    Restart-Service sshd
}

# ----------------------------------------------
# 2. Get Host IP for firewall restrictions
# ----------------------------------------------
$HostIP = Read-Host "Enter your Host OS (Physical PC) IP address (e.g., 192.168.0.66)"
$HostIP | Out-File -FilePath "C:\Lab4_HostIP.txt" -Force

# ----------------------------------------------
# 3. Identify internal interface (facing Relay)
# ----------------------------------------------
Write-Host "[INFO] Available network adapters:" -ForegroundColor Yellow
Get-NetAdapter | Where-Object Status -eq 'Up' | Format-Table Name, InterfaceDescription, Status
$internalIf = Read-Host "Enter the NAME of the internal interface (facing the Relay VM, e.g., 'Ethernet 2')"

# ----------------------------------------------
# 4. Configure static IP on internal interface: 192.168.99.1/29
# ----------------------------------------------
Write-Host "[ACTION] Setting static IP 192.168.99.1/29 on $internalIf ..." -ForegroundColor Yellow
# Remove any existing IP in the same subnet
Get-NetIPAddress -InterfaceAlias $internalIf -AddressFamily IPv4 | Where-Object { $_.IPAddress -like "192.168.99.*" } | Remove-NetIPAddress -Confirm:$false
New-NetIPAddress -InterfaceAlias $internalIf -IPAddress 192.168.99.1 -PrefixLength 29 -ErrorAction SilentlyContinue | Out-Null

# Ensure the external (NAT/bridged) interface uses DHCP
$externalIf = (Get-NetAdapter | Where-Object { $_.Name -ne $internalIf -and $_.Status -eq 'Up' }).Name
if ($externalIf) {
    Set-NetIPInterface -InterfaceAlias $externalIf -Dhcp Enabled -ErrorAction SilentlyContinue
    ipconfig /renew $externalIf | Out-Null
}

# ----------------------------------------------
# 5. Install Routing (NAT & IP forwarding)
# ----------------------------------------------
Write-Host "[ACTION] Enabling IP Forwarding and NAT for 192.168.99.0/29 ..." -ForegroundColor Yellow
$routingFeature = Get-WindowsFeature -Name Routing
if (-not $routingFeature.Installed) {
    Write-Host "[ACTION] Installing Routing feature..." -ForegroundColor Yellow
    Install-WindowsFeature -Name Routing -IncludeManagementTools | Out-Null
}

Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "IPEnableRouter" -Value 1 -Force
Start-Service RemoteAccess -ErrorAction SilentlyContinue

# Remove existing NAT and recreate for the internal subnet
Remove-NetNat -Name "LabNAT" -ErrorAction SilentlyContinue
New-NetNat -Name "LabNAT" -InternalIPInterfaceAddressPrefix "192.168.99.0/29" | Out-Null

# ----------------------------------------------
# 6. Install & configure DHCP Server for Relay
# ----------------------------------------------
Write-Host "[ACTION] Installing DHCP Server role..." -ForegroundColor Yellow
$dhcpFeature = Get-WindowsFeature -Name DHCP
if (-not $dhcpFeature.Installed) {
    Install-WindowsFeature -Name DHCP -IncludeManagementTools | Out-Null
}

# Ensure service is running
Start-Service DHCPServer -ErrorAction SilentlyContinue
Set-Service DHCPServer -StartupType Automatic

# Authorize DHCP server (required even in workgroup)
Add-DhcpServerInDC -DnsName $env:COMPUTERNAME -ErrorAction SilentlyContinue | Out-Null

# Create scope that gives exactly 192.168.99.2 to the Relay
$scopeName = "RelayScope"
$scope = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $scopeName }
if ($scope) {
    Remove-DhcpServerv4Scope -ScopeId $scope.ScopeId -Force -ErrorAction SilentlyContinue
}
Add-DhcpServerv4Scope -Name $scopeName `
    -StartRange 192.168.99.2 `
    -EndRange 192.168.99.2 `
    -SubnetMask 255.255.255.248 `
    -State Active | Out-Null

# Set DHCP options: default gateway = 192.168.99.1, DNS = 1.1.1.1, 8.8.8.8
Set-DhcpServerv4OptionValue -ScopeId 192.168.99.0 `
    -Router 192.168.99.1 `
    -DnsServer 1.1.1.1, 8.8.8.8 -ErrorAction SilentlyContinue | Out-Null

# ----------------------------------------------
# 7. Firewall rules (SSH from host, block ICMP from host, allow DHCP)
# ----------------------------------------------
Write-Host "[ACTION] Configuring firewall rules..." -ForegroundColor Yellow
Remove-NetFirewallRule -DisplayName "Lab4-Allow-SSH-Host","Lab4-Block-ICMP-Host" -ErrorAction SilentlyContinue

New-NetFirewallRule -DisplayName "Lab4-Allow-SSH-Host" `
    -Direction Inbound -LocalPort 22 -Protocol TCP -Action Allow `
    -RemoteAddress $HostIP -Profile Any | Out-Null

New-NetFirewallRule -DisplayName "Lab4-Block-ICMP-Host" `
    -Direction Inbound -Protocol ICMPv4 -IcmpType 8 -Action Block `
    -RemoteAddress $HostIP -Profile Any | Out-Null

# DHCP server already creates its own inbound rules (UDP 67). Optionally ensure they are enabled:
Enable-NetFirewallRule -DisplayGroup "DHCP Server" -ErrorAction SilentlyContinue

# ----------------------------------------------
# 8. Create persistent fwon / fwoff shortcuts (manage SSH/ICMP rules)
# ----------------------------------------------
Write-Host "[ACTION] Installing fwon and fwoff shortcuts..." -ForegroundColor Yellow
$LabDir = "C:\Lab4"
if (!(Test-Path $LabDir)) { New-Item -ItemType Directory -Path $LabDir | Out-Null }

$fwonScript = @'
$HostIPFile = "C:\Lab4_HostIP.txt"
if (Test-Path $HostIPFile) { $HostIP = Get-Content $HostIPFile } else { $HostIP = Read-Host "Enter Host OS IP" ; $HostIP | Out-File $HostIPFile -Force }
Remove-NetFirewallRule -DisplayName "Lab4-Allow-SSH-Host","Lab4-Block-ICMP-Host" -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "Lab4-Allow-SSH-Host" -Direction Inbound -LocalPort 22 -Protocol TCP -Action Allow -RemoteAddress $HostIP | Out-Null
New-NetFirewallRule -DisplayName "Lab4-Block-ICMP-Host" -Direction Inbound -Protocol ICMPv4 -IcmpType 8 -Action Block -RemoteAddress $HostIP | Out-Null
Start-Service sshd -ErrorAction SilentlyContinue
Write-Host "Firewall is now ON and persistent." -ForegroundColor Green
'@
$fwonScript | Out-File -FilePath "$LabDir\fwon.ps1" -Encoding utf8

$fwoffScript = @'
Remove-NetFirewallRule -DisplayName "Lab4-Allow-SSH-Host","Lab4-Block-ICMP-Host" -ErrorAction SilentlyContinue
Remove-Item -Path "C:\Lab4_HostIP.txt" -ErrorAction SilentlyContinue
Write-Host "Firewall rules are now PERMANENTLY OFF." -ForegroundColor Green
'@
$fwoffScript | Out-File -FilePath "$LabDir\fwoff.ps1" -Encoding utf8

"@echo off`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\Lab4\fwon.ps1'" | Out-File -FilePath "C:\Windows\fwon.cmd" -Encoding ascii
"@echo off`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\Lab4\fwoff.ps1'" | Out-File -FilePath "C:\Windows\fwoff.cmd" -Encoding ascii

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "  GATEWAY SETUP COMPLETE" -ForegroundColor Green
Write-Host "  - Internal interface: 192.168.99.1/29" -ForegroundColor Green
Write-Host "  - DHCP active: Relay will receive 192.168.99.2" -ForegroundColor Green
Write-Host "  - NAT enabled for 192.168.99.0/29" -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Cyan
