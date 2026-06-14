#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "  Lab 3/4: Windows Server 2022 Core Relay Setup" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

# ----------------------------------------------
# 1. Hardcoded interface names (no prompts, no auto-detection)
# ----------------------------------------------
$internalIf = "Ethernet"   # Facing Gateway (has 192.168.99.2)
$bridgedIf  = "Ethernet 2" # Facing Node (has 192.168.99.81)

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
# 3. Internal interface: ensure DHCP is enabled (to get 192.168.99.2 from Gateway)
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
# 4. IP Forwarding (registry) + Routing service
# ----------------------------------------------
$routingKey = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
$ipEnableRouter = Get-ItemProperty -Path $routingKey -Name "IPEnableRouter" -ErrorAction SilentlyContinue
if ($ipEnableRouter.IPEnableRouter -ne 1) {
    Write-Host "[ACTION] Enabling IP forwarding in registry..." -ForegroundColor Yellow
    Set-ItemProperty -Path $routingKey -Name "IPEnableRouter" -Value 1 -Force
}

$routingFeature = Get-WindowsFeature -Name Routing
if (-not $routingFeature.Installed) {
    Write-Host "[ACTION] Installing Routing feature..." -ForegroundColor Yellow
    Install-WindowsFeature -Name Routing -IncludeManagementTools | Out-Null
}

$ras = Get-Service RemoteAccess -ErrorAction SilentlyContinue
if ($ras.Status -ne 'Running') {
    Write-Host "[ACTION] Attempting to start RemoteAccess service..." -ForegroundColor Yellow
    Set-Service RemoteAccess -StartupType Automatic -ErrorAction SilentlyContinue
    try {
        Start-Service RemoteAccess -ErrorAction Stop
        Write-Host "[INFO] RemoteAccess service started successfully." -ForegroundColor Green
    } catch {
        Write-Host "[WARNING] RemoteAccess service could not be started. A reboot may be required for routing to work." -ForegroundColor Red
        Write-Host "[INFO] The service has been set to start automatically. Please reboot the Relay VM later." -ForegroundColor Yellow
    }
} else {
    Write-Host "[INFO] RemoteAccess service already running." -ForegroundColor Cyan
}

# ----------------------------------------------
# 5. DHCP Server for Node (feature, service, scope, reservation)
# ----------------------------------------------
$dhcpFeature = Get-WindowsFeature -Name DHCP
if (-not $dhcpFeature.Installed) {
    Write-Host "[ACTION] Installing DHCP Server feature..." -ForegroundColor Yellow
    Install-WindowsFeature -Name DHCP -IncludeManagementTools | Out-Null
}
$dhcpSvc = Get-Service DHCPServer -ErrorAction SilentlyContinue
if ($dhcpSvc.Status -ne 'Running') {
    Start-Service DHCPServer
    Set-Service DHCPServer -StartupType Automatic
}

# Authorize DHCP server only if domain-joined (otherwise ignore)
$domainStatus = (Get-CimInstance Win32_ComputerSystem).PartOfDomain
if ($domainStatus) {
    Write-Host "[INFO] Domain-joined – authorizing DHCP server..." -ForegroundColor Yellow
    Add-DhcpServerInDC -DnsName $env:COMPUTERNAME -ErrorAction SilentlyContinue | Out-Null
} else {
    Write-Host "[INFO] Workgroup environment – DHCP authorization skipped (not required)." -ForegroundColor Cyan
}

$nodeScopeId = "192.168.99.80"
$existingScope = Get-DhcpServerv4Scope -ScopeId $nodeScopeId -ErrorAction SilentlyContinue
if (-not $existingScope) {
    Write-Host "[ACTION] Creating DHCP scope for Node (assigns 192.168.99.82)..." -ForegroundColor Yellow
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
    Write-Host "[INFO] DHCP scope for Node (192.168.99.80/28) already exists." -ForegroundColor Cyan
}

# DHCP Reservation for Node VM (MAC 08-00-27-91-C0-11)
$nodeReservationIP = "192.168.99.82"
$nodeMAC = "08-00-27-91-C0-11"
$reservation = Get-DhcpServerv4Reservation -IPAddress $nodeReservationIP -ErrorAction SilentlyContinue
if (-not $reservation) {
    Write-Host "[ACTION] Creating DHCP reservation for Node VM ($nodeReservationIP -> $nodeMAC)..." -ForegroundColor Yellow
    Add-DhcpServerv4Reservation -ScopeId $nodeScopeId -IPAddress $nodeReservationIP -ClientId $nodeMAC -Description "Node VM" | Out-Null
    Write-Host "[INFO] Reservation added successfully." -ForegroundColor Green
} else {
    Write-Host "[INFO] DHCP reservation for $nodeReservationIP (MAC $nodeMAC) already exists." -ForegroundColor Cyan
}

# Ensure firewall allows DHCP traffic
Enable-NetFirewallRule -DisplayGroup "DHCP Server" -ErrorAction SilentlyContinue

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "  RELAY SETUP COMPLETE" -ForegroundColor Green
Write-Host "  - Internal ($internalIf) : should have 192.168.99.2 (from Gateway DHCP)" -ForegroundColor Green
Write-Host "  - Bridged ($bridgedIf)   : static 192.168.99.81/28" -ForegroundColor Green
Write-Host "  - DHCP server for Node ready (assigns 192.168.99.82)" -ForegroundColor Green
Write-Host "  - RESERVATION: 192.168.99.82 reserved for MAC 08-00-27-91-C0-11 (Node VM)" -ForegroundColor Green
if ((Get-Service RemoteAccess -ErrorAction SilentlyContinue).Status -ne 'Running') {
    Write-Host "  - [REBOOT RECOMMENDED] Restart Relay VM for routing to function." -ForegroundColor Red
}
Write-Host "=========================================================" -ForegroundColor Cyan
