#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "  Lab 4: Windows Server 2022 Core Gateway Setup" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

# 1. Get Host IP for Firewall Rules
$HostIP = Read-Host "🖥️ Enter your Host OS (Physical PC) IP address (e.g., 192.168.0.66)"
$HostIP | Out-File -FilePath "C:\Lab4_HostIP.txt" -Force

# 2. Install and Configure OpenSSH Server
Write-Host "📦 Installing OpenSSH Server..." -ForegroundColor Yellow
$sshCapability = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'
if ($sshCapability.State -ne 'Installed') {
    Add-WindowsCapability -Online -Name $sshCapability.Name | Out-Null
}

Start-Service sshd
Set-Service -Name sshd -StartupType Automatic

# Enable Password Authentication in sshd_config
$sshdConfigPath = "C:\ProgramData\ssh\sshd_config"
(Get-Content $sshdConfigPath) -replace '#PasswordAuthentication yes', 'PasswordAuthentication yes' | Set-Content $sshdConfigPath
(Get-Content $sshdConfigPath) -replace 'PasswordAuthentication no', 'PasswordAuthentication yes' | Set-Content $sshdConfigPath
Restart-Service sshd
Write-Host "   ✅ OpenSSH installed and configured for password login." -ForegroundColor Green

# 3. Configure STRICT Windows Firewall Rules
Write-Host "🔥 Applying STRICT Firewall Rules..." -ForegroundColor Yellow

# Remove old rules to prevent duplicates if script is run twice
Remove-NetFirewallRule -DisplayName "Lab4-Allow-SSH-Host" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "Lab4-Block-ICMP-Host" -ErrorAction SilentlyContinue

# ALLOW SSH ONLY from the specific Host IP
New-NetFirewallRule -DisplayName "Lab4-Allow-SSH-Host" `
    -Direction Inbound -LocalPort 22 -Protocol TCP -Action Allow `
    -RemoteAddress $HostIP -Profile Any | Out-Null

# EXPLICITLY BLOCK ICMPv4 Echo Request (Ping) from Host to prove it drops
New-NetFirewallRule -DisplayName "Lab4-Block-ICMP-Host" `
    -Direction Inbound -Protocol ICMPv4 -IcmpType 8 -Action Block `
    -RemoteAddress $HostIP -Profile Any | Out-Null

Write-Host "   ✅ Firewall configured: SSH Allowed, Ping Blocked." -ForegroundColor Green

# 4. Enable IP Forwarding and NAT (Lab 3 Continuity)
Write-Host "🌐 Enabling IP Forwarding and NAT for Relay/Node traffic..." -ForegroundColor Yellow
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "IPEnableRouter" -Value 1 -Force

# Setup Windows NAT (Assumes Internal interface facing Relay is on 192.168.99.0/29)
# If a NAT named 'LabNAT' already exists, this will silently skip
New-NetNat -Name "LabNAT" -InternalIPInterfaceAddressPrefix "192.168.99.0/29" -ErrorAction SilentlyContinue | Out-Null
Write-Host "   ✅ IP Routing and NAT enabled." -ForegroundColor Green

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "  ✅ GATEWAY SETUP COMPLETE!" -ForegroundColor Green
Write-Host "  From your Host OS, test:" -ForegroundColor Yellow
Write-Host "  1. ssh ubuntu@$((Get-NetIPAddress -AddressFamily IPv4 | Where-Object InterfaceAlias -notmatch 'Loopback' | Select-Object -First 1).IPAddress)" -ForegroundColor White
Write-Host "  2. ping <Gateway_IP> (Should DROP/Timeout)" -ForegroundColor White
Write-Host "=========================================================" -ForegroundColor Cyan