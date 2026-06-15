#Requires -RunAsAdministrator

# Enable IP forwarding on both interfaces (adjust names if needed)
Set-NetIPInterface -InterfaceAlias "Ethernet" -Forwarding Enabled
Set-NetIPInterface -InterfaceAlias "Ethernet 2" -Forwarding Enabled

# Start routing service
Set-Service RemoteAccess -StartupType Automatic
Start-Service RemoteAccess

# Add persistent route to Gateway (optional, but safe)
New-NetRoute -DestinationPrefix "192.168.99.0/24" -NextHop 192.168.99.1 -InterfaceAlias "Ethernet" -PolicyStore PersistentStore -ErrorAction SilentlyContinue

Write-Host "Relay routing enabled."
