#Requires -RunAsAdministrator

# ------------- Clean up old shortcuts -------------
$oldPaths = @(
    "C:\Windows\fwon.cmd",
    "C:\Windows\fwoff.cmd",
    "C:\Lab4\fwon.ps1",
    "C:\Lab4\fwoff.ps1"
)
foreach ($p in $oldPaths) {
    if (Test-Path $p) { Remove-Item -Path $p -Force }
}
Write-Host "Old shortcuts deleted."

# ------------- Create working directory -------------
$labDir = "C:\Lab4"
if (-not (Test-Path $labDir)) { New-Item -ItemType Directory -Path $labDir -Force | Out-Null }

# ------------- fwon.ps1 (with default/save behavior) -------------
$fwonScript = @'
# fwon.ps1 - Allow SSH, block ICMP from Host IP (with default/save)
$ErrorActionPreference = "Stop"
$hostIPFile = "C:\Lab4_HostIP.txt"

# Read saved IP if exists
$defaultIP = $null
if (Test-Path $hostIPFile) {
    $defaultIP = Get-Content $hostIPFile -Raw | ForEach-Object { $_.Trim() }
    if ($defaultIP) {
        $prompt = "Enter Host IP (default: $defaultIP): "
    } else {
        $prompt = "Enter Host IP: "
        $defaultIP = $null
    }
} else {
    $prompt = "Enter Host IP: "
    $defaultIP = $null
}

# Ask user for IP
$HostIP = Read-Host $prompt
if ([string]::IsNullOrWhiteSpace($HostIP)) {
    if ($defaultIP) {
        $HostIP = $defaultIP
        Write-Host "Using saved IP: $HostIP"
    } else {
        Write-Host "No IP provided. Exiting."
        exit 1
    }
}

# Validate IP (basic)
if ($HostIP -notmatch '^(\d{1,3}\.){3}\d{1,3}$') {
    Write-Host "Invalid IP address format. Exiting."
    exit 1
}

# Save the entered IP for next time
$HostIP | Out-File -FilePath $hostIPFile -Force

# Remove existing rules with same names to avoid duplicates
Remove-NetFirewallRule -DisplayName "Lab-Allow-SSH-Host" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "Lab-Block-ICMP-Host" -ErrorAction SilentlyContinue

# Allow SSH (TCP 22) only from Host IP
New-NetFirewallRule -DisplayName "Lab-Allow-SSH-Host" `
    -Direction Inbound -LocalPort 22 -Protocol TCP -Action Allow `
    -RemoteAddress $HostIP -Profile Any

# Block ICMP echo request (ping) from Host IP
New-NetFirewallRule -DisplayName "Lab-Block-ICMP-Host" `
    -Direction Inbound -Protocol ICMPv4 -IcmpType 8 -Action Block `
    -RemoteAddress $HostIP -Profile Any

Write-Host "Firewall rules applied: SSH allowed, ICMP blocked (only from $HostIP)." -ForegroundColor Green
'@

# ------------- fwoff.ps1 (unchanged) -------------
$fwoffScript = @'
# fwoff.ps1 - Remove the custom rules
Remove-NetFirewallRule -DisplayName "Lab-Allow-SSH-Host" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "Lab-Block-ICMP-Host" -ErrorAction SilentlyContinue
Write-Host "Custom firewall rules removed. Default behaviour restored." -ForegroundColor Green
'@

# Save the PowerShell scripts
$fwonScript | Out-File -FilePath "$labDir\fwon.ps1" -Encoding utf8 -Force
$fwoffScript | Out-File -FilePath "$labDir\fwoff.ps1" -Encoding utf8 -Force

# ------------- Create CMD shortcuts in C:\Windows -------------
$fwonCmd = @"
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$labDir\fwon.ps1"
"@

$fwoffCmd = @"
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$labDir\fwoff.ps1"
"@

$fwonCmd | Out-File -FilePath "C:\Windows\fwon.cmd" -Encoding ascii -Force
$fwoffCmd | Out-File -FilePath "C:\Windows\fwoff.cmd" -Encoding ascii -Force

Write-Host "Shortcuts recreated: 'fwon' and 'fwoff' are now available." -ForegroundColor Green
Write-Host "  - 'fwon' will show the last used IP as default." -ForegroundColor Cyan
Write-Host "  - Press Enter to keep it, or type a new IP." -ForegroundColor Cyan
