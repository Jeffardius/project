#Requires -RunAsAdministrator

Write-Host "Force-fixing Relay routing..."

# 1. Enable IP forwarding on both interfaces (use wildcard names if needed)
$ifs = @("Ethernet", "Ethernet 2")
foreach ($if in $ifs) {
    Set-NetIPInterface -InterfaceAlias $if -Forwarding Enabled -ErrorAction SilentlyContinue
}

# 2. Remove any existing NAT that might conflict (LabNAT is for Gateway, not Relay)
Get-NetNat | Remove-NetNat -Confirm:$false -ErrorAction SilentlyContinue

# 3. Restart routing service and ensure it stays
Stop-Service RemoteAccess -Force -ErrorAction SilentlyContinue
Set-Service RemoteAccess -StartupType Automatic
Start-Service RemoteAccess

# 4. Clear ARP cache on both interfaces
arp -d * 2>$null
Remove-NetNeighbor -InterfaceAlias $ifs -AddressFamily IPv4 -ErrorAction SilentlyContinue

# 5. Add explicit route to Gateway subnet via correct interface (ensure gateway reachable)
$gwIP = "192.168.99.1"
$internalIf = (Get-NetIPAddress -IPAddress $gwIP -ErrorAction SilentlyContinue).InterfaceAlias
if (-not $internalIf) {
    # If Relay can't see gateway IP, find interface with 192.168.99.2
    $internalIf = (Get-NetIPAddress -IPAddress "192.168.99.2" -ErrorAction SilentlyContinue).InterfaceAlias
}
if ($internalIf) {
    New-NetRoute -DestinationPrefix "192.168.99.0/24" -NextHop $gwIP -InterfaceAlias $internalIf -PolicyStore PersistentStore -ErrorAction SilentlyContinue
}

# 6. Disable Windows Firewall temporarily for testing (optional but effective)
netsh advfirewall set allprofiles state off

# 7. Verify forwarding
Write-Host "`n=== Current forwarding status ==="
Get-NetIPInterface -InterfaceAlias $ifs | Format-Table Name, Forwarding, Dhcp

Write-Host "`n=== Service status ==="
Get-Service RemoteAccess | Format-Table Name, Status, StartType

Write-Host "`n=== Routing table for 192.168.99.0/24 ==="
Get-NetRoute -DestinationPrefix "192.168.99.*" | Format-Table DestinationPrefix, NextHop, InterfaceAlias

Write-Host "`n[ACTION] Rebooting Relay in 5 seconds to fully apply routing..." -ForegroundColor Yellow
Start-Sleep -Seconds 5
Restart-Computer -Force
