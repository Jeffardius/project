#Requires -RunAsAdministrator
Write-Host "Fixing Relay forwarding (Node -> Gateway)..." -ForegroundColor Cyan

# 1. Enable forwarding on both interfaces
netsh interface ipv4 set interface "Ethernet" forwarding=enabled
netsh interface ipv4 set interface "Ethernet 2" forwarding=enabled
Write-Host "[OK] IP forwarding enabled on both interfaces" -ForegroundColor Green

# 2. Ensure default route points to Gateway (192.168.99.1)
$route = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue
if ($route) {
    if ($route.NextHop -ne "192.168.99.1") {
        Remove-NetRoute -DestinationPrefix "0.0.0.0/0" -Confirm:$false
        New-NetRoute -DestinationPrefix "0.0.0.0/0" -NextHop "192.168.99.1" -InterfaceAlias "Ethernet" | Out-Null
        Write-Host "[OK] Default route corrected to 192.168.99.1" -ForegroundColor Green
    } else {
        Write-Host "[OK] Default route already correct" -ForegroundColor Green
    }
} else {
    New-NetRoute -DestinationPrefix "0.0.0.0/0" -NextHop "192.168.99.1" -InterfaceAlias "Ethernet" | Out-Null
    Write-Host "[OK] Default route added" -ForegroundColor Green
}

# 3. Enable firewall rules for routing
Enable-NetFirewallRule -DisplayGroup "Routing and Remote Access" -ErrorAction SilentlyContinue
Write-Host "[OK] Routing firewall rules enabled" -ForegroundColor Green

# 4. Explicitly allow ICMP from Node to pass through Relay
New-NetFirewallRule -DisplayName "Allow ICMP from Node (Relay)" -Direction Inbound -Protocol ICMPv4 -IcmpType 8 -Action Allow -RemoteAddress 192.168.99.82/32 -InterfaceAlias "Ethernet" -ErrorAction SilentlyContinue | Out-Null
Write-Host "[OK] Firewall rule added for Node ICMP" -ForegroundColor Green

# 5. Restart RemoteAccess service
Restart-Service RemoteAccess -ErrorAction SilentlyContinue
Write-Host "[OK] RemoteAccess restarted" -ForegroundColor Green

Write-Host "`nRelay forwarding fix complete. Now test from Node: ping 192.168.99.1" -ForegroundColor Cyan
