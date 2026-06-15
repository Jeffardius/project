#Requires -RunAsAdministrator

Write-Host "===== VM Duplicate IP Address Fix =====" -ForegroundColor Cyan
Write-Host ""
Write-Host "This script will fix the '192.168.40.82' IP address conflict by:"
Write-Host "1. Resetting the network adapter"
Write-Host "2. Disabling Windows' duplicate IP detection"
Write-Host "3. Forcing a new IP address from the DHCP server"
Write-Host ""
Write-Host "Press any key to continue..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

# --- 1. Identify the network adapter and disable duplicate IP detection ---
$adapter = Get-NetAdapter -Name "Ethernet" -ErrorAction SilentlyContinue
if (-not $adapter) {
    Write-Host "Network adapter 'Ethernet' not found!" -ForegroundColor Red
    exit 1
}

Write-Host "Found adapter: $($adapter.Name) (MAC: $($adapter.MacAddress))" -ForegroundColor Green

Write-Host "Attempting to disable Duplicate Address Detection..." -ForegroundColor Yellow
try {
    Set-NetIPInterface -InterfaceAlias $adapter.Name -AddressFamily IPv4 -DadTransmits 0 -ErrorAction Stop
    Write-Host "Successfully disabled duplicate IP detection." -ForegroundColor Green
} catch {
    Write-Host "Could not disable Duplicate Address Detection. This might be because the setting is already applied." -ForegroundColor Yellow
}

# --- 2. Force a hard reset of the network adapter ---
Write-Host "Performing a hard reset of the network adapter..." -ForegroundColor Yellow
Restart-NetAdapter -Name $adapter.Name -Confirm:$false

Write-Host "Releasing current IP address..."
ipconfig /release

Write-Host "Waiting a moment before renewing..."
Start-Sleep -Seconds 3

Write-Host "Requesting a new IP address from the DHCP server..."
ipconfig /renew

# --- 3. Final check and reboot recommendation ---
Write-Host ""
Write-Host "===== Script Finished =====" -ForegroundColor Cyan
Write-Host ""
Write-Host "IMPORTANT: To ensure the fix is permanent, you MUST restart your VM now."
Write-Host ""
$restartChoice = Read-Host "Do you want to restart this VM now? (Y/N)"
if ($restartChoice -eq 'Y' -or $restartChoice -eq 'y') {
    Write-Host "Restarting VM in 5 seconds..."
    Start-Sleep -Seconds 5
    Restart-Computer -Force
} else {
    Write-Host "Remember to manually restart your VM for the changes to take full effect." -ForegroundColor Yellow
}
