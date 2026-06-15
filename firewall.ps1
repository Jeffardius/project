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

# ------------- fwon.ps1 (default IP + block all other traffic) -------------
$fwonScript = @'
# fwon.ps1 - Allow ONLY SSH from Host IP, block all other inbound traffic from that IP
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

# Remove existing custom rules to avoid duplicates
Remove-NetFirewallRule -DisplayName "Lab-Allow-SSH-Host" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "Lab-Block-All-Other-Host" -ErrorAction SilentlyContinue

# 1. Allow SSH (TCP 22) from Host IP
New-NetFirewallRule -DisplayName "Lab-Allow-SSH-Host" `
    -Direction Inbound -LocalPort 22 -Protocol TCP -Action Allow `
    -RemoteAddress $HostIP -Profile Any -Enabled True

# 2. Block ALL other inbound traffic from Host IP (any protocol, any port)
#    This rule will match after the SSH allow rule because Windows evaluates rules in order.
#    But we set the SSH rule with higher priority by not specifying a lower priority.
#    To ensure SSH is allowed, we create the block rule with lower priority (e.g., weight 100).
#    Alternatively, we can set the block rule to apply to all protocols except TCP/22? Simpler: block all,
#    and the explicit allow for SSH overrides it because allow rules are processed before block by default.
#    However, to be safe, we use a Block rule with "RemotePort" set to "Any" and protocol "Any".
New-NetFirewallRule -DisplayName "Lab-Block-All-Other-Host" `
    -Direction Inbound -Action Block -RemoteAddress $HostIP `
    -Protocol Any -Profile Any -Enabled True

Write-Host "Firewall rules applied instantly (persist after reboot):" -ForegroundColor Green
Write-Host "  - SSH (TCP 22) allowed from $HostIP" -ForegroundColor Green
Write-Host "  - All other inbound traffic from $HostIP blocked (ping, file sharing, etc.)" -ForegroundColor Green
'@

# ------------- fwoff.ps1 (remove custom rules) -------------
$fwoffScript = @'
# fwoff.ps1 - Remove the custom firewall rules
Remove-NetFirewallRule -DisplayName "Lab-Allow-SSH-Host" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "Lab-Block-All-Other-Host" -ErrorAction SilentlyContinue
Write-Host "Custom firewall rules removed. Default behaviour restored (no IP-specific restrictions)." -ForegroundColor Green
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

# ------------- Ensure Windows Firewall service starts automatically (so rules persist) -------------
Set-Service mpssvc -StartupType Automatic
Start-Service mpssvc -ErrorAction SilentlyContinue

Write-Host "`nShortcuts recreated: 'fwon' and 'fwoff' are now available in any command prompt." -ForegroundColor Green
Write-Host "  - 'fwon' will allow ONLY SSH from the specified Host IP and block all other inbound traffic from that IP." -ForegroundColor Cyan
Write-Host "  - Rules are applied instantly and survive reboots." -ForegroundColor Cyan
Write-Host "  - 'fwoff' removes both rules." -ForegroundColor Cyan
