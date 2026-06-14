#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "  Lab 4: Windows Server 2022 Core Gateway Setup" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

# 1. Install OpenSSH Server if missing
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

# 2. Get Host IP
$HostIP = Read-Host "Enter your Host OS (Physical PC) IP address (e.g., 192.168.0.66)"
$HostIP | Out-File -FilePath "C:\Lab4_HostIP.txt" -Force

# 3. Configure Strict Windows Firewall
Write-Host "[ACTION] Applying STRICT Firewall Rules..." -ForegroundColor Yellow
Remove-NetFirewallRule -DisplayName "Lab4-Allow-SSH-Host" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "Lab4-Block-ICMP-Host" -ErrorAction SilentlyContinue

New-NetFirewallRule -DisplayName "Lab4-Allow-SSH-Host" `
    -Direction Inbound -LocalPort 22 -Protocol TCP -Action Allow `
    -RemoteAddress $HostIP -Profile Any | Out-Null

New-NetFirewallRule -DisplayName "Lab4-Block-ICMP-Host" `
    -Direction Inbound -Protocol ICMPv4 -IcmpType 8 -Action Block `
    -RemoteAddress $HostIP -Profile Any | Out-Null

# 4. Enable IP Forwarding and NAT
Write-Host "[ACTION] Enabling IP Forwarding and NAT for 192.168.99.0/29..." -ForegroundColor Yellow
$routingFeature = Get-WindowsFeature -Name Routing
if (-not $routingFeature.Installed) {
    Write-Host "[ACTION] Installing Routing feature..." -ForegroundColor Yellow
    Install-WindowsFeature -Name Routing -IncludeManagementTools | Out-Null
}

Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "IPEnableRouter" -Value 1 -Force
Start-Service RemoteAccess -ErrorAction SilentlyContinue

# Setup Windows NAT for the internal network
Remove-NetNat -Name "LabNAT" -ErrorAction SilentlyContinue
New-NetNat -Name "LabNAT" -InternalIPInterfaceAddressPrefix "192.168.99.0/29" | Out-Null

# 5. Create Persistent fwon / fwoff Shortcuts
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
Write-Host "=========================================================" -ForegroundColor Cyan
