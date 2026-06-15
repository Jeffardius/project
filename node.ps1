#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "  Lab 3/4: Windows Server 2022 Core Node Setup" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

# Find all physical Ethernet adapters that are currently up
$adapters = Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Up' }

if (-not $adapters) {
    Write-Host "[ERROR] No active network adapter found. Exiting." -ForegroundColor Red
    exit 1
}

foreach ($adapter in $adapters) {
    $ifName = $adapter.Name
    Write-Host "[INFO] Processing adapter: $ifName" -ForegroundColor Yellow

    # Ensure DHCP is enabled on the IPv4 interface
    $dhcpStatus = Get-NetIPInterface -InterfaceAlias $ifName -AddressFamily IPv4 | Select-Object -ExpandProperty Dhcp
    if ($dhcpStatus -ne 'Enabled') {
        Write-Host "[ACTION] Enabling DHCP on $ifName ..." -ForegroundColor Yellow
        Set-NetIPInterface -InterfaceAlias $ifName -Dhcp Enabled
    } else {
        Write-Host "[INFO] DHCP already enabled on $ifName" -ForegroundColor Cyan
    }

    # Release current DHCP lease (if any) and request a fresh one
    Write-Host "[ACTION] Releasing and renewing DHCP lease on $ifName ..." -ForegroundColor Yellow
    ipconfig /release $ifName | Out-Null
    Start-Sleep -Seconds 2
    ipconfig /renew $ifName | Out-Null

    # Show the obtained IP address
    $ip = Get-NetIPAddress -InterfaceAlias $ifName -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if ($ip) {
        Write-Host "[SUCCESS] $ifName obtained IP: $($ip.IPAddress)" -ForegroundColor Green
    } else {
        Write-Host "[WARNING] $ifName did not receive an IPv4 address via DHCP." -ForegroundColor Red
    }
}

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "  NODE SETUP COMPLETE" -ForegroundColor Green
Write-Host "  The Node is now configured to obtain an IP dynamically." -ForegroundColor Green
Write-Host "  Expected IP (from Relay DHCP reservation): 192.168.99.82" -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Cyan
