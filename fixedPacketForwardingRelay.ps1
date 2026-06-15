#Requires -RunAsAdministrator

Write-Host "Configuring Relay routing (will reboot)..."

# 1. Enable IP forwarding on both interfaces
$ifs = @("Ethernet", "Ethernet 2")
foreach ($if in $ifs) {
    Set-NetIPInterface -InterfaceAlias $if -Forwarding Enabled -ErrorAction SilentlyContinue
}

# 2. Remove any existing NAT
Get-NetNat | Remove-NetNat -Confirm:$false -ErrorAction SilentlyContinue

# 3. Set RemoteAccess service to start automatically on boot
Set-Service RemoteAccess -StartupType Automatic -ErrorAction SilentlyContinue

# 4. Clear ARP cache
arp -d * 2>$null
Remove-NetNeighbor -InterfaceAlias $ifs -AddressFamily IPv4 -ErrorAction SilentlyContinue

# 5. Add persistent route to Gateway subnet
$gwIP = "192.168.99.1"
$internalIf = (Get-NetIPAddress -IPAddress "192.168.99.2" -ErrorAction SilentlyContinue).InterfaceAlias
if ($internalIf) {
    Remove-NetRoute -DestinationPrefix "192.168.99.0/24" -Confirm:$false -ErrorAction SilentlyContinue
    New-NetRoute -DestinationPrefix "192.168.99.0/24" -NextHop $gwIP -InterfaceAlias $internalIf -PolicyStore PersistentStore -ErrorAction SilentlyContinue
}

# 6. Disable firewall temporarily for testing
netsh advfirewall set allprofiles state off

Write-Host "Configuration complete. Rebooting in 5 seconds..."
Start-Sleep -Seconds 5
Restart-Computer -Force
