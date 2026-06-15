<#
.SYNOPSIS
    Configures IPv4 forwarding, disables the firewall temporarily, sets a default route, 
    restarts the RemoteAccess service, and clears the ARP cache.

.DESCRIPTION
    This script must be run as an Administrator. It is designed to troubleshoot or 
    initialize network routing on a Windows machine acting as a router/gateway.
#>

#Requires -RunAsAdministrator

# ==========================================
# CONFIGURATION VARIABLES
# ==========================================
$Interface1      = "Ethernet"
$Interface2      = "Ethernet 2"
$DefaultGateway  = "192.168.99.1"
$Destination     = "0.0.0.0/0"

# Prevent the script from stopping on non-terminating errors
$ErrorActionPreference = 'Continue'

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Starting Network Routing Configuration " -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# 1. Explicitly enable forwarding on both interfaces
Write-Host "[1/5] Enabling IPv4 forwarding on '$Interface1' and '$Interface2'..." -ForegroundColor Yellow
try {
    netsh interface ipv4 set interface "$Interface1" forwarding=enabled | Out-Null
    netsh interface ipv4 set interface "$Interface2" forwarding=enabled | Out-Null
    Write-Host "      -> Forwarding enabled successfully." -ForegroundColor Green
} catch {
    Write-Host "      -> Failed to enable forwarding: $($_.Exception.Message)" -ForegroundColor Red
}

# 2. Disable the Windows Firewall completely on all profiles (temporary test)
Write-Host "[2/5] Disabling Windows Firewall on all profiles (Temporary)..." -ForegroundColor Yellow
try {
    Set-NetFirewallProfile -All -Enabled False | Out-Null
    Write-Host "      -> Firewall disabled successfully." -ForegroundColor Green
    Write-Host "      -> WARNING: Remember to re-enable this after testing!" -ForegroundColor Red
} catch {
    Write-Host "      -> Failed to disable firewall: $($_. if (-not $route) {
        Write-Host "      -> No default route found. Creating new route..." -ForegroundColor Yellow
        New-NetRoute -DestinationPrefix $Destination -NextHop $DefaultGateway -InterfaceAlias $Interface1 | Out-Null
        Write-Host "      -> Route created successfully." -ForegroundColor Green
    } 
    elseif ($route.NextHop -ne $DefaultGateway) {
        Write-Host "      -> Existing route has incorrect NextHop ($($route.NextHop)). Updating..." -ForegroundColor Yellow
        Remove-NetRoute -DestinationPrefix $Destination -NextHop $route.NextHop -Confirm:$false -ErrorAction SilentlyContinue
        New-NetRoute -DestinationPrefix $Destination -NextHop $DefaultGateway -InterfaceAlias $Interface1 | Out-Null
        Write-Host "      -> Route updated successfully." -ForegroundColor Green
    } 
    else {
        Write-Host "      -> Default route is already correctly configured." -ForegroundColor Green
    }
} catch {
    Write-Host "      -> Failed to configure route: $($_.Exception.Message)" -ForegroundColor Red
}

# 4. Restart the IP forwarding service
Write-Host "[4/5] Restarting RemoteAccess service..." -ForegroundColor Yellow
try {
    # Check if service exists before trying to restart
    $service = Get-Service -Name RemoteAccess -ErrorAction SilentlyContinue
    if ($service) {
        Restart-Service -Name RemoteAccess -Force | Out-Null
        Write-Host "      -> RemoteAccess service restarted successfully." -ForegroundColor Green
    } else {
        Write-Host "      -> RemoteAccess service not found (skipping)." -ForegroundColor Gray
    }
} catch {
    Write-Host "      -> Failed to restart service: $($_.Exception.Message)" -ForegroundColor Red
}

# 5. Clear any stale ARP entries
Write-Host "[5/5] Clearing ARP cache..." -ForegroundColor Yellow
try {
    arp -d * | Out-Null
    Write-Host "      -> ARP cache cleared successfully." -ForegroundColor Green
} catch {
    Write-Host "      -> Failed to clear ARP cache: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Configuration Complete! " -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
