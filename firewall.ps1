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

if ($HostIP -notmatch '^(\d{1,3}\.){3}\d{1,3}$') {
    Write-Host "Invalid IP address format. Exiting."
    exit 1
}

$HostIP | Out-File -FilePath $hostIPFile -Force

Remove-NetFirewallRule -DisplayName "Lab-Allow-SSH-Host" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "Lab-Block-All-Other-Host" -ErrorAction SilentlyContinue

New-NetFirewallRule -DisplayName "Lab-Allow-SSH-Host" `
    -Direction Inbound -LocalPort 22 -Protocol TCP -Action Allow `
    -RemoteAddress $HostIP -Profile Any -Enabled True

New-NetFirewallRule -DisplayName "Lab-Block-All-Other-Host" `
    -Direction Inbound -Action Block -RemoteAddress $HostIP `
    -Protocol Any -Profile Any -Enabled True

Write-Host "Firewall rules applied instantly (persist after reboot):" -ForegroundColor Green
Write-Host "  - SSH (TCP 22) allowed from $HostIP" -ForegroundColor Green
Write-Host "  - All other inbound traffic from $HostIP blocked (ping, file sharing, etc.)" -ForegroundColor Green
'@

# ------------- fwoff.ps1 -------------
$fwoffScript = @'
Remove-NetFirewallRule -DisplayName "Lab-Allow-SSH-Host" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "Lab-Block-All-Other-Host" -ErrorAction SilentlyContinue
Write-Host "Custom firewall rules removed. Default behaviour restored." -ForegroundColor Green
'@

$fwonScript | Out-File -FilePath "$labDir\fwon.ps1" -Encoding utf8 -Force
$fwoffScript | Out-File -FilePath "$labDir\fwoff.ps1" -Encoding utf8 -Force

$fwonCmd = "@echo off`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$labDir\fwon.ps1`""
$fwoffCmd = "@echo off`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$labDir\fwoff.ps1`""

$fwonCmd | Out-File -FilePath "C:\Windows\fwon.cmd" -Encoding ascii -Force
$fwoffCmd | Out-File -FilePath "C:\Windows\fwoff.cmd" -Encoding ascii -Force

Write-Host "Shortcuts recreated: 'fwon' and 'fwoff' are now available in any command prompt." -ForegroundColor Green
