#Requires -RunAsAdministrator
Write-Host "===== RELAY ROUTING DIAGNOSTIC =====" -ForegroundColor Cyan

Write-Host "`n1. Forwarding status:" -ForegroundColor Yellow
netsh interface ipv4 show interface | findstr /i "Ethernet forwarding"

Write-Host "`n2. Default route:" -ForegroundColor Yellow
Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Format-Table -AutoSize

Write-Host "`n3. All routes for 192.168.99.0/24:" -ForegroundColor Yellow
Get-NetRoute -DestinationPrefix "192.168.99.*" | Format-Table -AutoSize

Write-Host "`n4. Interface IPs:" -ForegroundColor Yellow
Get-NetIPAddress -AddressFamily IPv4 | Where-Object InterfaceAlias -match "Ethernet" | Format-Table

Write-Host "`n5. ARP cache for 192.168.99.1 (Gateway):" -ForegroundColor Yellow
arp -a | findstr "192.168.99.1"

Write-Host "`n6. Can Relay ping Gateway?" -ForegroundColor Yellow
Test-Connection 192.168.99.1 -Count 2 -Quiet
