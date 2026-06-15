#Requires -RunAsAdministrator

Write-Host "Force-fixing Relay routing..."

# 1. Enable IP forwarding on both interfaces
$ifs = @("Ethernet", "Ethernet 2")
foreach ($if in $ifs) {
    Set-NetIPInterface -InterfaceAlias $if -Forwarding Enabled -ErrorAction SilentlyContinue
}

# 2. Remove any existing NAT that might conflict
Get-NetNat | Remove-NetNat -Confirm:$false -ErrorAction SilentlyContinue

# 3. Force-stop RemoteAccess service (kill process if necessary)
Write-Host "Stopping RemoteAccess service..."
net stop RemoteAccess /y 2>$null
Stop-Process -Name "svchost" -ErrorAction SilentlyContinue -Force 2>$null
Stop-Service RemoteAccess -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Kill the RAS process if still running
$rasProcess = Get-Process -Name "rasmans" -ErrorAction SilentlyContinue
if ($rasProcess) {
    $rasProcess | Stop-Process -Force
    Start-Sleep -Seconds 2
}

# 4. Set service to auto and start fresh
Set-Service RemoteAccess -StartupType Automatic
Start-Service RemoteAccess -ErrorAction SilentlyContinue

# 5. Clear ARP cache
arp -d * 2>$null
Remove-NetNeighbor -InterfaceAlias $ifs -AddressFamily IPv4 -ErrorAction SilentlyContinue

# 6. Add explicit route to Gateway subnet
$gwIP = "192.168.99.1"
$internalIf = (Get-NetIPAddress -IPAddress "192.168.99.2" -ErrorAction SilentlyContinue).InterfaceAlias
if ($internalIf) {
    Remove-NetRoute -DestinationPrefix "192.168.99.0/24" -Confirm:$false -ErrorAction SilentlyContinue
    New-NetRoute -DestinationPrefix "192.168.99.0/24" -NextHop $gwIP -InterfaceAlias $internalIf -PolicyStore PersistentStore -ErrorAction SilentlyContinue
}

# 7. Temporarily disable firewall for testing
netsh advfirewall set allprofiles state off

# 8. Verify
Write-Host "`n=== Forwarding status ==="
Get-NetIPInterface -InterfaceAlias $ifs | Format-Table Name, Forwarding

Write-Host "`n=== RemoteAccess service ==="
Get-Service RemoteAccess | Format-Table Name, Status, StartType

Write-Host "`n=== Route to Gateway ==="
Get-NetRoute -DestinationPrefix "192.168.99.0/24"

Write-Host "`n[ACTION] Rebooting in 5 seconds..."
Start-Sleep -Seconds 5
Restart-Computer -Force
