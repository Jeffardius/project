#Requires -RunAsAdministrator

Write-Host "Disabling Duplicate Address Detection (DAD) on all IPv4 interfaces..." -ForegroundColor Cyan

# Get all IPv4 interfaces that are "up" (excluding loopback and disconnected)
$interfaces = Get-NetIPInterface -AddressFamily IPv4 | Where-Object {
    $_.InterfaceAlias -notlike '*Loopback*' -and $_.InterfaceMetric -ne 0
}

if (-not $interfaces) {
    Write-Host "No active IPv4 interfaces found." -ForegroundColor Red
    exit 1
}

foreach ($if in $interfaces) {
    Write-Host "Processing: $($if.InterfaceAlias)" -ForegroundColor Yellow
    Set-NetIPInterface -InterfaceAlias $if.InterfaceAlias -AddressFamily IPv4 -DadTransmits 0 -ErrorAction SilentlyContinue
    if ($?) {
        Write-Host "  DAD disabled." -ForegroundColor Green
    } else {
        Write-Host "  Failed (might already be disabled)." -ForegroundColor Gray
    }
}

Write-Host "`nDone. No other changes were made." -ForegroundColor Green
Write-Host "You can now restart your network adapter or reboot if needed." -ForegroundColor Yellow
