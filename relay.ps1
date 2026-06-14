#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

Write-Host "🔧 Installing persistent 'fwon' and 'fwoff' shortcuts..." -ForegroundColor Cyan

# 1. Create the Lab4 directory
$LabDir = "C:\Lab4"
if (!(Test-Path $LabDir)) { New-Item -ItemType Directory -Path $LabDir | Out-Null }

# 2. Create fwon.ps1 (Strict Firewall ON)
$fwonScript = @'
#Requires -RunAsAdministrator
$HostIPFile = "C:\Lab4_HostIP.txt"

# Get Host IP (prompt if not saved)
if (Test-Path $HostIPFile) {
    $HostIP = Get-Content $HostIPFile
} else {
    $HostIP = Read-Host "🖥️ Enter your Host OS (Physical PC) IP address (e.g., 192.168.0.66)"
    $HostIP | Out-File -FilePath $HostIPFile -Force
}

Write-Host "⚙️ Applying STRICT Firewall Rules (SSH Allowed, Ping Blocked)..." -ForegroundColor Yellow

# Remove old rules to prevent duplicates
Remove-NetFirewallRule -DisplayName "Lab4-Allow-SSH-Host" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "Lab4-Block-ICMP-Host" -ErrorAction SilentlyContinue

# ALLOW SSH ONLY from the specific Host IP
New-NetFirewallRule -DisplayName "Lab4-Allow-SSH-Host" `
    -Direction Inbound -LocalPort 22 -Protocol TCP -Action Allow `
    -RemoteAddress $HostIP -Profile Any | Out-Null

# EXPLICITLY BLOCK ICMPv4 Echo Request (Ping) from Host
New-NetFirewallRule -DisplayName "Lab4-Block-ICMP-Host" `
    -Direction Inbound -Protocol ICMPv4 -IcmpType 8 -Action Block `
    -RemoteAddress $HostIP -Profile Any | Out-Null

# Ensure SSH Service is running
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic

Write-Host "✅ Firewall is now ON and PERSISTENT." -ForegroundColor Green
Write-Host "   - SSH from $HostIP : ALLOWED" -ForegroundColor Green
Write-Host "   - Ping/Other traffic: BLOCKED" -ForegroundColor Green
'@
$fwonScript | Out-File -FilePath "$LabDir\fwon.ps1" -Encoding utf8

# 3. Create fwoff.ps1 (Firewall OFF Permanently)
$fwoffScript = @'
#Requires -RunAsAdministrator
Write-Host "🔥 Permanently disabling Lab 4 strict firewall rules..." -ForegroundColor Yellow

# Remove the strict Lab 4 rules
Remove-NetFirewallRule -DisplayName "Lab4-Allow-SSH-Host" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "Lab4-Block-ICMP-Host" -ErrorAction SilentlyContinue

# Delete the saved IP file so fwon prompts again next time
Remove-Item -Path "C:\Lab4_HostIP.txt" -ErrorAction SilentlyContinue

Write-Host "✅ Firewall rules are now PERMANENTLY OFF." -ForegroundColor Green
Write-Host "💡 They will stay off across reboots until you run 'fwon' again."
'@
$fwoffScript | Out-File -FilePath "$LabDir\fwoff.ps1" -Encoding utf8

# 4. Create .cmd wrappers in C:\Windows so they act as global commands
$fwonCmd = "@echo off`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\Lab4\fwon.ps1'"
$fwoffCmd = "@echo off`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\Lab4\fwoff.ps1'"

$fwonCmd | Out-File -FilePath "C:\Windows\fwon.cmd" -Encoding ascii
$fwoffCmd | Out-File -FilePath "C:\Windows\fwoff.cmd" -Encoding ascii

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "  ✅ SHORTCUTS INSTALLED SUCCESSFULLY!" -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "You can now type these commands from ANYWHERE:" -ForegroundColor Yellow
Write-Host "  fwon   -> Turns strict firewall ON (Persists across reboots)"
Write-Host "  fwoff  -> Turns firewall OFF permanently (Persists across reboots)"