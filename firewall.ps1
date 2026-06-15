#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

Write-Host "Installing firewall control shortcuts 'fwon' and 'fwoff'..." -ForegroundColor Cyan

# ---------- Clean up old shortcuts ----------
$oldPaths = @(
    "C:\Windows\fwon.cmd",
    "C:\Windows\fwoff.cmd",
    "C:\Lab4\fwon.ps1",
    "C:\Lab4\fwoff.ps1"
)
foreach ($p in $oldPaths) {
    if (Test-Path $p) { Remove-Item -Path $p -Force }
}

# ---------- Create working directory ----------
$labDir = "C:\Lab4"
if (-not (Test-Path $labDir)) { New-Item -ItemType Directory -Path $labDir -Force | Out-Null }

# ---------- fwon.ps1 (main script) ----------
$fwonScript = @'
# fwon.ps1 - Allow ONLY SSH from Host IP, block ALL other inbound traffic (including ping)
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

# Basic validation
if ($HostIP -notmatch '^(\d{1,3}\.){3}\d{1,3}$') {
    Write-Host "Invalid IP address format. Exiting."
    exit 1
}

# Save the entered IP for next time
$HostIP | Out-File -FilePath $hostIPFile -Force

# Remove any existing custom rules to avoid duplicates
Remove-NetFirewallRule -DisplayName "Lab-Allow-SSH-Host" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "Lab-Block-ICMP-From-Host" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "Lab-Block-All-Other-Host" -ErrorAction SilentlyContinue

# Disable the default Windows ICMP rule (so that our block can take effect)
$defaultICMP = "File and Printer Sharing (Echo Request - ICMPv4-In)"
Set-NetFirewallRule -DisplayName $defaultICMP -Enabled False -ErrorAction SilentlyContinue

# 1. Allow SSH (TCP 22) from Host IP
New-NetFirewallRule -DisplayName "Lab-Allow-SSH-Host" `
    -Direction Inbound -LocalPort 22 -Protocol TCP -Action Allow `
    -RemoteAddress $HostIP -Profile Any -Enabled True

# 2. Explicitly block ICMP echo requests (ping) from Host IP
New-NetFirewallRule -DisplayName "Lab-Block-ICMP-From-Host" `
    -Direction Inbound -Protocol ICMPv4 -IcmpType 8 -Action Block `
    -RemoteAddress $HostIP -Profile Any -Enabled True

# 3. Block ALL other inbound traffic (any protocol, any port) from Host IP
New-NetFirewallRule -DisplayName "Lab-Block-All-Other-Host" `
    -Direction Inbound -Action Block -RemoteAddress $HostIP `
    -Protocol Any -Profile Any -Enabled True

Write-Host "Firewall rules applied: SSH allowed, all else (including ping) blocked from $HostIP." -ForegroundColor Green
'@

# ---------- fwoff.ps1 (removal script) ----------
$fwoffScript = @'
# fwoff.ps1 - Remove the custom firewall rules and restore default ICMP behaviour
Remove-NetFirewallRule -DisplayName "Lab-Allow-SSH-Host" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "Lab-Block-ICMP-From-Host" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "Lab-Block-All-Other-Host" -ErrorAction SilentlyContinue

# Re-enable the default Windows ICMP rule
$defaultICMP = "File and Printer Sharing (Echo Request - ICMPv4-In)"
Set-NetFirewallRule -DisplayName $defaultICMP -Enabled True -ErrorAction SilentlyContinue

Write-Host "Custom firewall rules removed. Default behaviour restored (ping allowed again)." -ForegroundColor Green
'@

# ---------- Save the PowerShell scripts ----------
$fwonScript | Out-File -FilePath "$labDir\fwon.ps1" -Encoding utf8 -Force
$fwoffScript | Out-File -FilePath "$labDir\fwoff.ps1" -Encoding utf8 -Force

# ---------- Create CMD shortcuts in C:\Windows ----------
$fwonCmd = "@echo off`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$labDir\fwon.ps1`""
$fwoffCmd = "@echo off`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$labDir\fwoff.ps1`""

$fwonCmd | Out-File -FilePath "C:\Windows\fwon.cmd" -Encoding ascii -Force
$fwoffCmd | Out-File -FilePath "C:\Windows\fwoff.cmd" -Encoding ascii -Force

# ---------- Final message ----------
Write-Host "`nInstallation complete!" -ForegroundColor Green
Write-Host "You can now use the following commands in any Command Prompt (run as Administrator):" -ForegroundColor Cyan
Write-Host "  fwon  - Apply firewall rules (allow SSH, block everything else from your Host IP)" -ForegroundColor White
Write-Host "  fwoff - Remove the rules (restore normal firewall behaviour)" -ForegroundColor White
Write-Host ""
Write-Host "The Host IP will be saved and used as default next time you run 'fwon'." -ForegroundColor Cyan
