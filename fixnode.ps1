#Requires -RunAsAdministrator
Write-Host "Fixing Node to allow pings and set default gateway..." -ForegroundColor Cyan

# 1. Set default gateway to Relay's bridged IP
Write-Host "[1/4] Setting default gateway to 192.168.99.81"
$adapter = (Get-NetAdapter -Name "Ethernet").Name
Set-NetIPInterface -InterfaceAlias $adapter -Dhcp Disabled
New-NetIPAddress -InterfaceAlias $adapter -IPAddress 192.168.99.82 -PrefixLength 28 -DefaultGateway 192.168.99.81 -ErrorAction SilentlyContinue | Out-Null

# 2. Allow all ICMPv4 (echo request and reply)
Write-Host "[2/4] Enabling ICMP in Windows Firewall"
netsh advfirewall firewall add rule name="Allow ICMPv4 In" dir=in action=allow protocol=icmpv4
netsh advfirewall firewall add rule name="Allow ICMPv4 Out" dir=out action=allow protocol=icmpv4

# 3. Disable firewall completely for a test (optional, can remove later)
Write-Host "[3/4] Temporarily disabling firewall (to confirm fix)"
Set-NetFirewallProfile -All -Enabled False

# 4. Flush DNS and ARP
Write-Host "[4/4] Flushing ARP and DNS"
ipconfig /flushdns
arp -d

Write-Host "`nAll done. Now test from Node:" -ForegroundColor Green
Write-Host "   ping 192.168.99.1" -ForegroundColor Yellow
Write-Host "   ping 8.8.8.8" -ForegroundColor Yellow

# Test
ping 192.168.99.1 -n 2
