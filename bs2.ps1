# Node_Diagnostic.ps1 – Run as Administrator on Node VM
Write-Host "=== NODE DIAGNOSTIC ===" -ForegroundColor Cyan

# 1. IP configuration
$ipConfig = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike "*Loopback*" }
$defaultGateway = (Get-NetRoute -DestinationPrefix "0.0.0.0/0").NextHop
$dnsServers = (Get-DnsClientServerAddress -AddressFamily IPv4).ServerAddresses

Write-Host "`n[1] IPv4 Configuration:" -ForegroundColor Yellow
foreach ($ip in $ipConfig) {
    Write-Host "  Interface: $($ip.InterfaceAlias)"
    Write-Host "    IP: $($ip.IPAddress)/$($ip.PrefixLength)"
}
Write-Host "  Default Gateway: $defaultGateway"
Write-Host "  DNS Servers: $($dnsServers -join ', ')"

# 2. Test connectivity
$relayIP = "192.168.99.81"
$gatewayIP = "192.168.99.1"
$testIPs = @($relayIP, $gatewayIP, "1.1.1.1", "8.8.8.8")

Write-Host "`n[2] Connectivity Tests (ping):" -ForegroundColor Yellow
foreach ($ip in $testIPs) {
    $result = Test-Connection -ComputerName $ip -Count 2 -Quiet
    if ($result) {
        Write-Host "  $ip -> OK" -ForegroundColor Green
    } else {
        Write-Host "  $ip -> FAILED" -ForegroundColor Red
    }
}

# 3. Routing table (only relevant entries)
Write-Host "`n[3] IPv4 Routing Table:" -ForegroundColor Yellow
Get-NetRoute -AddressFamily IPv4 | Where-Object { $_.DestinationPrefix -ne "255.255.255.255/32" } | Format-Table DestinationPrefix, NextHop, InterfaceAlias, RouteMetric -AutoSize

# 4. ARP cache for Gateway and Relay
Write-Host "`n[4] ARP Cache (Gateway & Relay):" -ForegroundColor Yellow
arp -a | Select-String -Pattern "$gatewayIP|$relayIP"

# 5. DHCP lease info
Write-Host "`n[5] DHCP Lease Details:" -ForegroundColor Yellow
ipconfig /all | Select-String -Pattern "DHCP Enabled|Lease Obtained|Lease Expires"

# 6. Suggestions
Write-Host "`n[6] DIAGNOSIS & SUGGESTIONS:" -ForegroundColor Cyan

# Check default gateway
if (-not $defaultGateway) {
    Write-Host "  - No default gateway! Node cannot reach outside its subnet." -ForegroundColor Red
    Write-Host "    ACTION: On Node, run 'ipconfig /renew'. If still missing, check Relay's DHCP scope options." -ForegroundColor Yellow
} elseif ($defaultGateway -ne $relayIP) {
    Write-Host "  - Default gateway is $defaultGateway, but should be $relayIP (Relay's bridged IP)." -ForegroundColor Red
    Write-Host "    ACTION: On Relay, ensure DHCP scope option 'Router' is set to $relayIP." -ForegroundColor Yellow
} else {
    Write-Host "  - Default gateway is correct ($relayIP)." -ForegroundColor Green
}

# Check ping to Relay
$pingRelay = Test-Connection -ComputerName $relayIP -Count 1 -Quiet
if (-not $pingRelay) {
    Write-Host "  - Cannot ping Relay ($relayIP). Check:" -ForegroundColor Red
    Write-Host "      * Are Node and Relay on the same virtual switch?" -ForegroundColor Yellow
    Write-Host "      * Is Relay's bridged interface ($relayIP) up and no firewall blocking ICMP?" -ForegroundColor Yellow
} else {
    Write-Host "  - Can ping Relay – Layer 2 is good." -ForegroundColor Green
}

# Check ping to Gateway
$pingGateway = Test-Connection -ComputerName $gatewayIP -Count 1 -Quiet
if (-not $pingGateway) {
    Write-Host "  - Cannot ping Gateway ($gatewayIP). Possible causes:" -ForegroundColor Red
    Write-Host "      * Relay is not forwarding packets between its two interfaces." -ForegroundColor Yellow
    Write-Host "      * IP forwarding/routing is disabled on Relay." -ForegroundColor Yellow
    Write-Host "      * Gateway's internal interface has DHCP still enabled (stealing IP)." -ForegroundColor Yellow
    Write-Host "    ACTION ON RELAY (as Admin):" -ForegroundColor Cyan
    Write-Host "        Get-NetIPInterface | Where-Object {$_.Forwarding -eq 'Disabled'}" -ForegroundColor White
    Write-Host "        Set-NetIPInterface -InterfaceAlias 'Ethernet','Ethernet 2' -Forwarding Enabled" -ForegroundColor White
    Write-Host "        Get-Service RemoteAccess | Start-Service" -ForegroundColor White
    Write-Host "        netsh routing ip nat install" -ForegroundColor White
} else {
    Write-Host "  - Can ping Gateway – Relay is routing correctly." -ForegroundColor Green
}

# Check internet connectivity via ping 1.1.1.1
$pingInternet = Test-Connection -ComputerName "1.1.1.1" -Count 1 -Quiet
if (-not $pingInternet) {
    Write-Host "  - Cannot reach internet (1.1.1.1). After fixing Gateway ping, check:" -ForegroundColor Red
    Write-Host "      * Does Gateway have NAT or a route back to Node's subnet?" -ForegroundColor Yellow
    Write-Host "      * On Gateway, NAT should be configured for 192.168.99.0/24 (as in your script)." -ForegroundColor Yellow
} else {
    Write-Host "  - Internet reachable – all good!" -ForegroundColor Green
}

Write-Host "`n=== End of Diagnostic ===" -ForegroundColor Cyan
