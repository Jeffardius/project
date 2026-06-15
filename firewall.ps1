#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

# ---------- 1. CLEANUP ----------
$oldPaths = @(
    "C:\Windows\fwon.cmd", "C:\Windows\fwoff.cmd",
    "C:\Lab4\fwon.ps1", "C:\Lab4\fwoff.ps1"
)
foreach ($p in $oldPaths) { if (Test-Path $p) { Remove-Item -Path $p -Force } }

# ---------- 2. DIRECTORIES ----------
$labDir = "C:\Lab4"
if (-not (Test-Path $labDir)) { New-Item -ItemType Directory -Path $labDir -Force | Out-Null }

# ---------- 3. FWON (APPLY RULES) ----------
$fwonScript = @'
# fwon.ps1
$ErrorActionPreference = "Stop"
$hostIPFile = "C:\Lab4_HostIP.txt"
$defaultIP = $null
if (Test-Path $hostIPFile) {
    $defaultIP = Get-Content $hostIPFile -Raw | ForEach-Object { $_.Trim() }
    $prompt = "Enter Host IP (default: $defaultIP): "
} else {
    $prompt = "Enter Host IP: "
}
$HostIP = Read-Host $prompt
if ([string]::IsNullOrWhiteSpace($HostIP)) {
    if ($defaultIP) { $HostIP = $defaultIP } else { exit 1 }
}
if ($HostIP -notmatch '^(\d{1,3}\.){3}\d{1,3}$') { exit 1 }
$HostIP | Out-File -FilePath $hostIPFile -Force

# Remove existing custom rules to avoid duplicates
Remove-NetFirewallRule -DisplayName "Lab-Allow-SSH-Host" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "Lab-Block-All-Other-Host" -ErrorAction SilentlyContinue

# --- 3a: Turn OFF the default ICMP rule (so our block will work) ---
$defaultICMP = "File and Printer Sharing (Echo Request - ICMPv4-In)"
Set-NetFirewallRule -DisplayName $defaultICMP -Enabled False -ErrorAction SilentlyContinue

# --- 3b: Add the Allow SSH rule (Highest priority) ---
New-NetFirewallRule -DisplayName "Lab-Allow-SSH-Host" `
    -Direction Inbound -LocalPort 22 -Protocol TCP -Action Allow `
    -RemoteAddress $HostIP -Profile Any -Enabled True

# --- 3c: Add the Block All rule (Second priority) ---
New-NetFirewallRule -DisplayName "Lab-Block-All-Other-Host" `
    -Direction Inbound -Action Block -RemoteAddress $HostIP `
    -Protocol Any -Profile Any -Enabled True

Write-Host "Rules active: SSH allowed, all else blocked from $HostIP." -ForegroundColor Green
'@

# ---------- 4. FWOFF (REMOVE RULES) ----------
$fwoffScript = @'
# fwoff.ps1
Remove-NetFirewallRule -DisplayName "Lab-Allow-SSH-Host" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "Lab-Block-All-Other-Host" -ErrorAction SilentlyContinue

# Re-enable the default ICMP rule after fwoff
$defaultICMP = "File and Printer Sharing (Echo Request - ICMPv4-In)"
Set-NetFirewallRule -DisplayName $defaultICMP -Enabled True -ErrorAction SilentlyContinue

Write-Host "Custom rules removed, default ICMP rule re-enabled." -ForegroundColor Green
'@

# Save the scripts
$fwonScript | Out-File -FilePath "$labDir\fwon.ps1" -Encoding utf8 -Force
$fwoffScript | Out-File -FilePath "$labDir\fwoff.ps1" -Encoding utf8 -Force

# Create CMD shortcuts in C:\Windows
$fwonCmd = "@echo off`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$labDir\fwon.ps1`""
$fwoffCmd = "@echo off`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$labDir\fwoff.ps1`""
$fwonCmd | Out-File -FilePath "C:\Windows\fwon.cmd" -Encoding ascii -Force
$fwoffCmd | Out-File -FilePath "C:\Windows\fwoff.cmd" -Encoding ascii -Force

Write-Host "Setup complete: 'fwon' and 'fwoff' are ready to use." -ForegroundColor Green
