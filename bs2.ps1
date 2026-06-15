# Find the internal interface (the one with the static IP 192.168.99.1)
$internalIf = (Get-NetIPAddress -IPAddress 192.168.99.1 -ErrorAction SilentlyContinue).InterfaceAlias
if ($internalIf) {
    Set-NetIPInterface -InterfaceAlias $internalIf -Dhcp Disabled
    Write-Host "DHCP disabled on internal interface $internalIf" -ForegroundColor Green
} else {
    Write-Host "Internal interface with IP 192.168.99.1 not found" -ForegroundColor Red
}
