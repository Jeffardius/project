#Requires -RunAsAdministrator

# 1. Enable IP forwarding on both network interfaces
Set-NetIPInterface -InterfaceAlias "Ethernet" -Forwarding Enabled
Set-NetIPInterface -InterfaceAlias "Ethernet 2" -Forwarding Enabled

# 2. Start and enable the Routing (RemoteAccess) service
Set-Service RemoteAccess -StartupType Automatic
Start-Service RemoteAccess

# 3. Clear any stale ARP entries that might point to the wrong MAC
Clear-NetNeighbor -InterfaceAlias "Ethernet","Ethernet 2" -AddressFamily IPv4

# 4. Add a persistent default route if missing (optional but safe)
$route = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -NextHop 192.168.99.1 -ErrorAction SilentlyContinue
if (-not $route) {
    New-NetRoute -DestinationPrefix "0.0.0.0/0" -NextHop 192.168.99.1 -InterfaceAlias "Ethernet" -PolicyStore PersistentStore
}

Write-Host "Relay routing enabled. Reboot the Relay or restart the RemoteAccess service to apply fully."
