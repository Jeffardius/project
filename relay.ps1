#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "  Lab 3/4: Windows Server 2022 Core Relay Setup" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

# ----------------------------------------------
# 1. Hardcoded interface names
# ----------------------------------------------
$internalIf = "Ethernet"   # Facing Gateway (gets DHCP 192.168.99.2)
$bridgedIf  = "Ethernet 2" # Facing Node (static 192.168.99.81)

# Verify both interfaces exist and are up
$eth1 = Get-NetAdapter -Name $internalIf -ErrorAction SilentlyContinue
$eth2 = Get-NetAdapter -Name $bridgedIf -ErrorAction SilentlyContinue

if (-not $eth1 -or $eth1.Status -ne 'Up') {
    Write-Host "[ERROR] Interface '$internalIf' not found or not UP. Exiting." -ForegroundColor Red
    exit 1
}
if (-not $eth2 -or $eth2.Status -ne 'Up') {
    Write-Host "[ERROR] Interface '$bridgedIf' not found or not UP. Exiting." -ForegroundColor Red
    exit 1
}

Write-Host "[INFO] Using interfaces:" -ForegroundColor Yellow
Write-Host "   Internal (to Gateway): $internalIf" -ForegroundColor Green
Write-Host "   Bridged (to Node)    : $bridgedIf" -ForegroundColor Green

# ----------------------------------------------
# 2. Configure bridged interface static IP (192.168.99.81/28)
# ----------------------------------------------
$targetIP = "192.168.99.81"
$prefix = 28
$currentBridgedIP = Get-NetIPAddress -InterfaceAlias $bridgedIf -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -eq $targetIP -and $_.PrefixLength -eq $prefix }
if (-not $currentBridgedIP) {
    Write-Host "[ACTION] Setting static IP $targetIP/$prefix on $bridgedIf ..." -ForegroundColor Yellow
    Get-NetIPAddress -InterfaceAlias $bridgedIf -AddressFamily IPv4 | Where-Object { $_.IPAddress -like "192.168.99.*" } | Remove-NetIPAddress -Confirm:$false
    New-NetIPAddress -InterfaceAlias $bridgedIf -IPAddress $targetIP -PrefixLength $prefix | Out-Null
} else {
    Write-Host "[INFO] Bridged interface already has correct IP $targetIP/$prefix" -ForegroundColor Cyan
}

# ----------------------------------------------
# 3. Internal interface: ensure DHCP is enabled
# ----------------------------------------------
$dhcpStatus = Get-NetIPInterface -InterfaceAlias $internalIf | Select-Object -ExpandProperty Dhcp
if ($dhcpStatus -ne 'Enabled') {
    Write-Host "[ACTION] Setting internal interface $internalIf to DHCP..." -ForegroundColor Yellow
    Set-NetIPInterface -InterfaceAlias $internalIf -Dhcp Enabled
    ipconfig /renew $internalIf | Out-Null
} else {
    Write-Host "[INFO] Internal interface already using DHCP" -ForegroundColor Cyan
}

# ----------------------------------------------
# 4. IP Forwarding (registry, interface forwarding, routing service)
# ----------------------------------------------
Write-Host "[ACTION] Configuring IP forwarding..." -ForegroundColor Yellow

$routingKey = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
$ipEnableRouter = Get-ItemProperty -Path $routingKey -Name "IPEnableRouter" -ErrorAction SilentlyContinue
if ($ipEnableRouter.IPEnableRouter -ne 1) {
    Write-Host "  - Enabling IP forwarding in registry..." -ForegroundColor Yellow
    Set-ItemProperty -Path $routingKey -Name "IPEnableRouter" -Value 1 -Force
}

# Explicitly enable forwarding on each interface
Write-Host "  - Enabling forwarding on $internalIf..." -ForegroundColor Yellow
netsh interface ipv4 set interface "$internalIf" forwarding=enabled | Out-Null
Write-Host "  - Enabling forwarding on $bridgedIf..." -ForegroundColor Yellow
netsh interface ipv4 set interface "$bridgedIf" forwarding=enabled | Out-Null

# Install Routing feature if not present
$routingFeature = Get-WindowsFeature -Name Routing
if (-not $routingFeature.Installed) {
    Write-Host "  - Installing Routing feature..." -ForegroundColor Yellow
    Install-WindowsFeature -Name Routing -IncludeManagementTools | Out-Null
}

# Start RemoteAccess service
$ras = Get-Service RemoteAccess -ErrorAction SilentlyContinue
if ($ras.Status -ne 'Running') {
    Write-Host "  - Setting RemoteAccess service to Automatic..." -ForegroundColor Yellow
    Set-Service RemoteAccess -StartupType Automatic -ErrorAction SilentlyContinue
    try {
        Start-Service RemoteAccess -ErrorAction Stop
        Write-Host "  - RemoteAccess service started successfully." -ForegroundColor Green
    } catch {
        Write-Host "  - [WARNING] RemoteAccess service could not be started. A reboot will be required." -ForegroundColor Red
        Write-Host "  - The service has been set to start automatically. Please reboot the Relay VM later." -ForegroundColor Yellow
    }
} else {
    Write-Host "  - RemoteAccess service already running." -ForegroundColor Cyan
}

# Enable firewall rules for routing
Write-Host "  - Enabling Routing and Remote Access firewall rules..." -ForegroundColor Yellow
Enable-NetFirewallRule -DisplayGroup "Routing and Remote Access" -ErrorAction SilentlyContinue

# Ensure a default route exists
$defaultRoute = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue
if (-not $defaultRoute) {
    Write-Host "  - Adding default route via 192.168.99.1 on $internalIf..." -ForegroundColor Yellow
    New-NetRoute -DestinationPrefix "0.0.0.0/0" -NextHop "192.168.99.1" -InterfaceAlias $internalIf -ErrorAction SilentlyContinue | Out-Null
} else {
    Write-Host "  - Default route already exists." -ForegroundColor Cyan
}

# ----------------------------------------------
# 5. DHCP Server for Node
# ----------------------------------------------
Write-Host "[ACTION] Configuring DHCP server for Node..." -ForegroundColor Yellow

$dhcpFeature = Get-WindowsFeature -Name DHCP
if (-not $dhcpFeature.Installed) {
    Write-Host "  - Installing DHCP Server feature..." -ForegroundColor Yellow
    Install-WindowsFeature -Name DHCP -IncludeManagementTools | Out-Null
}
$dhcpSvc = Get-Service DHCPServer -ErrorAction SilentlyContinue
if ($dhcpSvc.Status -ne 'Running') {
    Start-Service DHCPServer
    Set-Service DHCPServer -StartupType Automatic
}

$domainStatus = (Get-WmiObject Win32_ComputerSystem).PartOfDomain
if ($domainStatus) {
    Write-Host "  - Domain-joined – authorizing DHCP server..." -ForegroundColor Yellow
    Add-DhcpServerInDC -DnsName $env:COMPUTERNAME -ErrorAction SilentlyContinue | Out-Null
} else {
    Write-Host "  - Workgroup environment – DHCP authorization skipped." -ForegroundColor Cyan
}

$nodeScopeId = "192.168.99.80"
$existingScope = Get-DhcpServerv4Scope -ScopeId $nodeScopeId -ErrorAction SilentlyContinue
if (-not $existingScope) {
    Write-Host "  - Creating DHCP scope for Node (assigns 192.168.99.82)..." -ForegroundColor Yellow
    Add-DhcpServerv4Scope -Name "NodeScope" `
        -StartRange 192.168.99.82 `
        -EndRange 192.168.99.82 `
        -SubnetMask 255.255.255.240 `
        -State Active | Out-Null
    
    $dnsServers = @("8.8.8.8", "8.8.4.4")
    Set-DhcpServerv4OptionValue -ScopeId $nodeScopeId `
        -Router 192.168.99.81 `
        -DnsServer $dnsServers -ErrorAction Stop | Out-Null
} else {
    Write-Host "  - DHCP scope for Node already exists." -ForegroundColor Cyan
}

$nodeReservationIP = "192.168.99.82"
$nodeMAC = "08-00-27-91-C0-11"
$reservation = Get-DhcpServerv4Reservation -IPAddress $nodeReservationIP -ErrorAction SilentlyContinue
if (-not $reservation) {
    Write-Host "  - Creating DHCP reservation for Node VM ($nodeReservationIP -> $nodeMAC)..." -ForegroundColor Yellow
    Add-DhcpServerv4Reservation -ScopeId $nodeScopeId -IPAddress $nodeReservationIP -ClientId $nodeMAC -Description "Node VM" | Out-Null
    Write-Host "  - Reservation added successfully." -ForegroundColor Green
} else {
    Write-Host "  - DHCP reservation already exists." -ForegroundColor Cyan
}

Enable-NetFirewallRule -DisplayGroup "DHCP Server" -ErrorAction SilentlyContinue

# ----------------------------------------------
# Final status
# ----------------------------------------------
Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "  RELAY SETUP COMPLETE" -ForegroundColor Green
Write-Host "  - Internal ($internalIf) : should have 192.168.99.2 (from Gateway DHCP)" -ForegroundColor Green
Write-Host "  - Bridged ($bridgedIf)   : static 192.168.99.81/28" -ForegroundColor Green
Write-Host "  - DHCP server ready (assigns 192.168.99.82 to Node)" -ForegroundColor Green
Write-Host "  - IP forwarding enabled on both interfaces" -ForegroundColor Green

$rasRunning = (Get-Service RemoteAccess -ErrorAction SilentlyContinue).Status -eq 'Running'
if (-not $rasRunning) {
    Write-Host "  - [REBOOT REQUIRED] RemoteAccess service not started. Routing will work after reboot." -ForegroundColor Red
} else {
    Write-Host "  - Routing is active – Node should reach Gateway and Internet." -ForegroundColor Green
}
Write-Host "=========================================================" -ForegroundColor Cyan
