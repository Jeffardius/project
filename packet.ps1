#Requires -RunAsAdministrator
Write-Host "Starting capture (no compression)..." -ForegroundColor Cyan
$file = "C:\relay.etl"
pktmon start --capture -f $file
Write-Host "Capturing for 10 seconds... Make sure Node is pinging continuously." -ForegroundColor Yellow
Start-Sleep -Seconds 10
pktmon stop
pktmon format $file -o C:\relay.txt
Write-Host "`nLooking for ICMP from Node (MAC 08-00-27-91-C0-11)..." -ForegroundColor Cyan
Select-String -Path C:\relay.txt -Pattern "08-00-27-91-C0-11|ICMP"
