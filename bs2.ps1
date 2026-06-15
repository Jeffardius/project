#Requires -RunAsAdministrator
Write-Host "Fixing asymmetric forwarding on Relay..." -ForegroundColor Cyan

# 1. Ensure forwarding is enabled on both interfaces
netsh interface ipv4 set interface "Ethernet" forwarding=enabled
netsh interface ipv4 set interface "Ethernet 2" forwarding=enabled

# 2. Delete any default route that is NOT 192.168.99.1
$badRoutes = Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Where-Object { $_.NextHop -ne "192.168.99.1" }
foreach ($r in $badRoutes) {
    Write-Host "Removing incorrect default route via $($r.NextHop) on $($r.InterfaceAlias)"
    Remove-NetRoute -DestinationPrefix "0.0.0.0/0" -NextHop $r.NextHop -InterfaceAlias $r.InterfaceAlias -Confirm:$false
}

# 3. Add correct default route (if missing)
$correctRoute = Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Where-Object { $_.NextHop -eq "192.168.99.1" -and $_.InterfaceAlias -eq "Ethernet" }
if (-not $correctRoute) {
    Write-Host "Adding default route via 192.168.99.1 on Ethernet"
    New-NetRoute -DestinationPrefix "0.0.0.0/0" -NextHop "192.168.99.1" -InterfaceAlias "Ethernet" -RouteMetric 1 | Out-Null
}

# 4. Lower the metric on the internal interface to prefer it
Set-NetIPInterface -InterfaceAlias "Ethernet" -InterfaceMetric 10
Set-NetIPInterface -InterfaceAlias "Ethernet 2" -InterfaceMetric 20

# 5. Disable Windows Firewall completely for a test (temporary)
Set-NetFirewallProfile -All -Enabled False
Write-Host "Firewall disabled temporarily for test." -ForegroundColor Yellow

# 6. Flush ARP and restart routing
arp -d
Restart-Service RemoteAccess -ErrorAction SilentlyContinue

Write-Host "`nNow test from Node: ping 192.168.99.1 and ping 8.8.8.8" -ForegroundColor Green
Write-Host "If it works, re-enable firewall and add rules. If still fails, reboot Relay and test again." -ForegroundColor Yellow
