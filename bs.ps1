#Requires -RunAsAdministrator

Write-Host "Re-applying relay routing after reboot..."

# 1. Enable IP forwarding on both interfaces (by name, adjust if different)
Set-NetIPInterface -InterfaceAlias "Ethernet" -Forwarding Enabled
Set-NetIPInterface -InterfaceAlias "Ethernet 2" -Forwarding Enabled

# 2. Force set IP forwarding in registry (survives reboot)
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "IPEnableRouter" -Value 1 -Force

# 3. Ensure RemoteAccess service is running
Stop-Service RemoteAccess -ErrorAction SilentlyContinue
Set-Service RemoteAccess -StartupType Automatic
Start-Service RemoteAccess

# 4. Clear any stale ARP
arp -d *
Remove-NetNeighbor -InterfaceAlias "Ethernet","Ethernet 2" -AddressFamily IPv4 -ErrorAction SilentlyContinue

# 5. Re-add persistent route to gateway subnet (if missing)
$route = Get-NetRoute -DestinationPrefix "192.168.99.0/24" -ErrorAction SilentlyContinue
if (-not $route) {
    New-NetRoute -DestinationPrefix "192.168.99.0/24" -NextHop 192.168.99.1 -InterfaceAlias "Ethernet" -PolicyStore PersistentStore
}

# 6. Disable Windows Firewall on relay temporarily (for testing)
netsh advfirewall set allprofiles state off

# 7. Test relay's own connectivity to gateway and internet
Write-Host "`nTesting relay connectivity..."
ping -n 2 192.168.99.1
ping -n 2 1.1.1.1

Write-Host "`nRouting and forwarding should now be active."
Write-Host "If internet still fails from node, check gateway's NAT."
