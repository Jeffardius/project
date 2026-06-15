#Requires -RunAsAdministrator
Write-Host "Enabling NAT on Relay for Node subnet..." -ForegroundColor Cyan

# Install Remote Access (if not already)
Install-WindowsFeature -Name Routing -IncludeManagementTools -ErrorAction SilentlyContinue

# Configure NAT: internal interface (to Gateway) and private interface (to Node)
netsh routing ip nat install
netsh routing ip nat add interface "Ethernet" mode=full
netsh routing ip nat add interface "Ethernet 2" mode=private

# Enable forwarding
Set-NetIPInterface -InterfaceAlias "Ethernet" -Forwarding Enabled
Set-NetIPInterface -InterfaceAlias "Ethernet 2" -Forwarding Enabled

# Restart service
Restart-Service RemoteAccess

Write-Host "NAT configured. Now Node should reach Gateway and Internet." -ForegroundColor Green
