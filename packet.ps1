#Requires -RunAsAdministrator
Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "  Relay Packet Capture - Node to Gateway Path" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

$captureFile = "C:\relay_capture.etl"
$outputFile = "C:\relay_capture.txt"

Write-Host "[1/5] Starting packet capture on Relay..." -ForegroundColor Yellow
pktmon start --capture --pkt-size 128 --compression -f $captureFile

Write-Host "[2/5] Waiting for pings from Node..." -ForegroundColor Yellow
Write-Host "   ACTION: On the NODE VM, run: ping 192.168.99.1" -ForegroundColor Green
Write-Host "   WAITING 15 seconds... (press any key to skip wait)" -ForegroundColor Cyan
$timeout = 15
for ($i = $timeout; $i -gt 0; $i--) {
    Write-Host "   `r$i seconds remaining..." -NoNewline
    Start-Sleep -Seconds 1
}
Write-Host "`r   Capture window closed." -ForegroundColor Gray

Write-Host "[3/5] Stopping packet capture..." -ForegroundColor Yellow
pktmon stop

Write-Host "[4/5] Converting capture to readable text..." -ForegroundColor Yellow
pktmon format $captureFile -o $outputFile

Write-Host "[5/5] Analyzing capture for ICMP packets..." -ForegroundColor Yellow
Write-Host "`n=========================================================" -ForegroundColor Cyan
Write-Host "  RESULTS - Look for ICMP traffic" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

# Search for relevant patterns
Select-String -Path $outputFile -Pattern "ICMP|192.168.99.82|192.168.99.1|Node|Gateway" | Select-Object -First 30

Write-Host "`n=========================================================" -ForegroundColor Cyan
Write-Host "  CAPTURE COMPLETE" -ForegroundColor Green
Write-Host "  Full log saved to: $outputFile" -ForegroundColor Yellow
Write-Host "  To manually inspect: notepad $outputFile" -ForegroundColor Yellow
Write-Host "=========================================================" -ForegroundColor Cyan
