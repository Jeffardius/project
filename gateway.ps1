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
    Write-Host "[SUCCESS] OpenSSH Server installed." -ForegroundColor Green
} else {
    Write-Host "[SUCCESS] OpenSSH Server is already installed." -ForegroundColor Green
}

# 2. Configure SSH for Password Login
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
    Write-Host "[SUCCESS] SSH configured and restarted." -ForegroundColor Green
}

# 3. Get Host IP
$HostIP = Read-Host "Enter your Host OS (Physical PC) IP address (e.g., 192.168.0.66)"
$HostIP | Out-File -FilePath "C:\Lab4_HostIP.txt" -Force

# 4. Configure Windows Firewall
Write-Host "[ACTION] Applying STRICT Firewall Rules..." -ForegroundColor Yellow
Remove-NetFirewallRule -DisplayName "Lab4-Allow-SSH-Host" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "Lab4-Block-ICMP-Host" -ErrorAction SilentlyContinue

New-NetFirewallRule -DisplayName "Lab4-Allow-SSH-Host" `
    -Direction Inbound -LocalPort 22 -Protocol TCP -Action Allow `
    -RemoteAddress $HostIP -Profile Any | Out-Null

New-NetFirewallRule -DisplayName "Lab4-Block-ICMP-Host" `
    -Direction Inbound -Protocol ICMPv4 -IcmpType 8 -Action Block `
    -RemoteAddress $HostIP -Profile Any | Out-Null
Write-Host "[SUCCESS] Firewall configured: SSH Allowed, Ping Blocked." -ForegroundColor Green

# 5. Enable IP Forwarding and NAT
Write-Host "[ACTION] Enabling IP Forwarding and NAT..." -ForegroundColor Yellow
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "IPEnableRouter" -Value 1 -Force

# Install Routing feature if needed for NetNat command
$routingFeature = Get-WindowsFeature -Name RSAT-RemoteAccess
if (-not $routingFeature.Installed) {
    Write-Host "[ACTION] Installing RemoteAccess RSAT tools for NAT..." -ForegroundColor Yellow
    Install-WindowsFeature -Name RSAT-RemoteAccess -IncludeAllSubFeature | Out-Null
}

Remove-NetNat -Name "LabNAT" -ErrorAction SilentlyContinue
New-NetNat -Name "LabNAT" -InternalIPInterfaceAddressPrefix "192.168.99.0/29" | Out-Null
Write-Host "[SUCCESS] IP Routing and NAT enabled." -ForegroundColor Green

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "  GATEWAY SETUP COMPLETE!" -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Cyan