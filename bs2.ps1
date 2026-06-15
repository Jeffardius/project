#Requires -RunAsAdministrator
Write-Host "Allowing Gateway to accept pings from Node..." -ForegroundColor Cyan

# Allow ICMP from Node's subnet (or specific IP 192.168.99.82)
New-NetFirewallRule -DisplayName "Allow ping from Node" -Direction Inbound -Protocol ICMPv4 -IcmpType 8 -Action Allow -RemoteAddress 192.168.99.82/32 -ErrorAction SilentlyContinue | Out-Null
Write-Host "[OK] Firewall rule added on Gateway" -ForegroundColor Green

Write-Host "`nGateway is now pingable from Node." -ForegroundColor Cyan
