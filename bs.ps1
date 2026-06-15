#Requires -RunAsAdministrator

Write-Host "=== Attempt to add static IP on host's subnet ===" -ForegroundColor Cyan

# --- Configuration ---
$HostSubnet = "10.33.28.0"
$PrefixLength = 24
$GatewayIP = "10.33.28.1"   # Adjust to your actual network gateway
$StaticIP = "10.33.28.200"  # Choose an unused IP in your host's subnet

# --- Identify the active network adapter ---
$adapter = Get-NetAdapter -Name "Ethernet" -ErrorAction SilentlyContinue
if (-not $adapter) {
    Write-Host "Ethernet adapter not found. Listing all adapters:" -ForegroundColor Yellow
    Get-NetAdapter | Where-Object {$_.Status -eq 'Up'} | Format-Table Name, InterfaceDescription
    $adapterName = Read-Host "Enter the name of your network adapter"
    $adapter = Get-NetAdapter -Name $adapterName
}

Write-Host "Using adapter: $($adapter.Name)" -ForegroundColor Green

# --- Add a static IP on the host's subnet (preserving the existing NAT IP) ---
Write-Host "Adding static IP $StaticIP/$PrefixLength (Gateway: $GatewayIP) ..." -ForegroundColor Yellow
New-NetIPAddress -InterfaceAlias $adapter.Name -IPAddress $StaticIP -PrefixLength $PrefixLength -DefaultGateway $GatewayIP -ErrorAction SilentlyContinue

# --- Disable DAD to avoid IP conflicts ---
Set-NetIPInterface -InterfaceAlias $adapter.Name -AddressFamily IPv4 -DadTransmits 0

Write-Host "`nNow test from your host: ping $StaticIP" -ForegroundColor Cyan
Write-Host "If this works, use that IP for SSH (e.g., ssh Administrator@$StaticIP)" -ForegroundColor Green
