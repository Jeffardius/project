#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "  Lab 4: Windows Server 2022 Core Gateway Setup" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

# ----------------------------------------------
# 1. OpenSSH Server (only if missing or misconfigured)
# ----------------------------------------------
$sshCapability = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'
if ($sshCapability.State -ne 'Installed') {
    Write-Host "[ACTION] Installing OpenSSH Server..." -ForegroundColor Yellow
    Add-WindowsCapability -Online -Name $sshCapability.Name | Out-Null
}

$sshdConfigPath = "$env:ProgramData\ssh\sshd_config"
if (Test-Path $sshdConfigPath) {
    $currentConfig = Get-Content $sshdConfigPath -Raw
    if ($currentConfig -notmatch '^PasswordAuthentication yes' -and $currentConfig -match 'PasswordAuthentication no') {
        Write-Host "[ACTION] Enabling password authentication in SSH config..." -ForegroundColor Yellow
        $newConfig = $currentConfig -replace '#PasswordAuthentication yes', 'PasswordAuthentication yes'
        $newConfig = $newConfig -replace 'PasswordAuthentication no', 'PasswordAuthentication yes'
        Set-Content $sshdConfigPath $newConfig
        Restart-Service sshd
    }
}
if ((Get-Service sshd -ErrorAction SilentlyContinue).Status -ne 'Running') {
    Start-Service sshd
    Set-Service sshd -StartupType Automatic
}

# ----------------------------------------------
# 2. Get Host IP for firewall rules (store for later)
# ----------------------------------------------
$hostIPFile = "C:\Lab4_HostIP.txt"
if (-not (Test-Path $hostIPFile)) {
    $HostIP = Read-Host "Enter your Host OS (Physical PC) IP address (e.g., 192.168.0.66)"
    $HostIP | Out-File -FilePath $hostIPFile -Force
} else {
    $HostIP = Get-Content $hostIPFile
    Write-Host "[INFO] Using saved Host IP: $HostIP" -ForegroundColor Cyan
}

# ----------------------------------------------
# 3. Determine interfaces (internal = second up adapter)
# ----------------------------------------------
$adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
if ($adapters.Count -lt 2) {
    Write-Host "[ERROR] Less than 2 network adapters are Up. Exiting." -ForegroundColor Red
    exit 1
}
$internalIf = $adapters[1].Name
$externalIf  = $adapters[0].Name
Write-Host "[INFO] External interface: $externalIf (DHCP)" -ForegroundColor Green
Write-Host "[INFO] Internal interface: $internalIf (will be 192.168.99.1/29)" -ForegroundColor Green

# ----------------------------------------------
# 4. Configure static IP on internal interface (FORCE SET)
# ----------------------------------------------
$targetIP = "192.168.99.1"
$prefix = 29

Write-Host "[ACTION] Force setting static IP $targetIP/$prefix on $internalIf ..." -ForegroundColor Yellow

# Remove ALL IPv4 addresses on this interface (to avoid conflicts)
Get-NetIPAddress -InterfaceAlias $internalIf -AddressFamily IPv4 -ErrorAction SilentlyContinue | 
    Remove-NetIPAddress -Confirm:$false

# Now add the desired static IP
New-NetIPAddress -InterfaceAlias $internalIf -IPAddress $targetIP -PrefixLength $prefix | Out-Null

# Ensure interface is up (enable it if disabled)
if ((Get-NetAdapter -Name $internalIf).Status -ne 'Up') {
    Write-Host "[ACTION] Enabling adapter $internalIf ..." -ForegroundColor Yellow
    Enable-NetAdapter -Name $internalIf -ErrorAction SilentlyContinue
}

# Verify
$check = Get-NetIPAddress -InterfaceAlias $internalIf -AddressFamily IPv4 | Where-Object { $_.IPAddress -eq $targetIP }
if (-not $check) {
    Write-Host "[ERROR] Failed to set static IP on $internalIf" -ForegroundColor Red
    exit 1
}
Write-Host "[INFO] Static IP $targetIP/$prefix successfully set on $internalIf" -ForegroundColor Green

# Ensure external interface uses DHCP
$extDhcp = Get-NetIPInterface -InterfaceAlias $externalIf | Select-Object -ExpandProperty Dhcp
if ($extDhcp -ne 'Enabled') {
    Write-Host "[ACTION] Setting external interface $externalIf to DHCP..." -ForegroundColor Yellow
    Set-NetIPInterface -InterfaceAlias $externalIf -Dhcp Enabled
    ipconfig /renew $externalIf | Out-Null
}

# ----------------------------------------------
# 5. IP Forwarding (registry) + Routing service
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
        Write-Host "[WARNING] RemoteAccess service could not be started. A reboot may be required for NAT to work." -ForegroundColor Red
        Write-Host "[INFO] The service has been set to start automatically. Please reboot the Gateway VM later." -ForegroundColor Yellow
    }
} else {
    Write-Host "[INFO] RemoteAccess service already running." -ForegroundColor Cyan
}

# ----------------------------------------------
# 6. NAT (only if missing)
# ----------------------------------------------
$natExists = Get-NetNat -Name "LabNAT" -ErrorAction SilentlyContinue
if (-not $natExists) {
    Write-Host "[ACTION] Creating NAT for 192.168.99.0/29..." -ForegroundColor Yellow
    New-NetNat -Name "LabNAT" -InternalIPInterfaceAddressPrefix "192.168.99.0/29" | Out-Null
} else {
    Write-Host "[INFO] NAT 'LabNAT' already exists." -ForegroundColor Cyan
}

# ----------------------------------------------
# 7. DHCP Server (feature, service, scope)
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
$domainStatus = (Get-WmiObject Win32_ComputerSystem).PartOfDomain
if ($domainStatus) {
    Write-Host "[INFO] Domain-joined – authorizing DHCP server..." -ForegroundColor Yellow
    Add-DhcpServerInDC -DnsName $env:COMPUTERNAME -ErrorAction SilentlyContinue | Out-Null
} else {
    Write-Host "[INFO] Workgroup environment – DHCP authorization skipped (not required)." -ForegroundColor Cyan
}

# Bind DHCP to internal interface
Add-DhcpServerv4Binding -InterfaceAlias $internalIf -ErrorAction SilentlyContinue

$scopeId = "192.168.99.0"
$existingScope = Get-DhcpServerv4Scope -ScopeId $scopeId -ErrorAction SilentlyContinue
if (-not $existingScope) {
    Write-Host "[ACTION] Creating DHCP scope for Relay (assigns 192.168.99.2)..." -ForegroundColor Yellow
    Add-DhcpServerv4Scope -Name "RelayScope" `
        -StartRange 192.168.99.2 `
        -EndRange 192.168.99.2 `
        -SubnetMask 255.255.255.248 `
        -State Active | Out-Null
    Set-DhcpServerv4OptionValue -ScopeId $scopeId `
        -Router 192.168.99.1 `
        -DnsServer "8.8.8.8", "8.8.4.4" | Out-Null
} else {
    Write-Host "[INFO] DHCP scope for 192.168.99.0/29 already exists." -ForegroundColor Cyan
}

# ----------------------------------------------
# 8. Firewall rules (only if missing)
# ----------------------------------------------
$sshRule = Get-NetFirewallRule -DisplayName "Lab4-Allow-SSH-Host" -ErrorAction SilentlyContinue
if (-not $sshRule) {
    Write-Host "[ACTION] Creating firewall rule: allow SSH from host..." -ForegroundColor Yellow
    New-NetFirewallRule -DisplayName "Lab4-Allow-SSH-Host" `
        -Direction Inbound -LocalPort 22 -Protocol TCP -Action Allow `
        -RemoteAddress $HostIP -Profile Any | Out-Null
}
$icmpRule = Get-NetFirewallRule -DisplayName "Lab4-Block-ICMP-Host" -ErrorAction SilentlyContinue
if (-not $icmpRule) {
    Write-Host "[ACTION] Creating firewall rule: block ICMP from host..." -ForegroundColor Yellow
    New-NetFirewallRule -DisplayName "Lab4-Block-ICMP-Host" `
        -Direction Inbound -Protocol ICMPv4 -IcmpType 8 -Action Block `
        -RemoteAddress $HostIP -Profile Any | Out-Null
}
Enable-NetFirewallRule -DisplayGroup "DHCP Server" -ErrorAction SilentlyContinue

# ----------------------------------------------
# 9. Create fwon / fwoff shortcuts (ALWAYS recreate)
# ----------------------------------------------
$LabDir = "C:\Lab4"
if (-not (Test-Path $LabDir)) { New-Item -ItemType Directory -Path $LabDir | Out-Null }

$fwonPath = "$LabDir\fwon.ps1"
$fwoffPath = "$LabDir\fwoff.ps1"

Write-Host "[ACTION] Creating/updating fwon.ps1 and fwoff.ps1..." -ForegroundColor Yellow

$fwonScript = @'
$HostIPFile = "C:\Lab4_HostIP.txt"
if (Test-Path $HostIPFile) {
    $HostIP = Get-Content $HostIPFile
} else {
    $HostIP = Read-Host "Enter your Host OS IP address"
    $HostIP | Out-File $HostIPFile -Force
}

Remove-NetFirewallRule -DisplayName "Lab4-Allow-SSH-Host" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "Lab4-Block-ICMP-Host" -ErrorAction SilentlyContinue

Disable-NetFirewallRule -DisplayGroup "File and Printer Sharing" -Direction Inbound -ErrorAction SilentlyContinue

New-NetFirewallRule -DisplayName "Lab4-Allow-SSH-Host" `
    -Direction Inbound -LocalPort 22 -Protocol TCP -Action Allow `
    -RemoteAddress $HostIP -Profile Any | Out-Null

New-NetFirewallRule -DisplayName "Lab4-Block-ICMP-Host" `
    -Direction Inbound -Protocol ICMPv4 -IcmpType 8 -Action Block `
    -RemoteAddress $HostIP -Profile Any | Out-Null

Start-Service sshd -ErrorAction SilentlyContinue
Write-Host "Firewall ON: SSH allowed (only from $HostIP), ICMP blocked (only from $HostIP)." -ForegroundColor Green
'@

$fwoffScript = @'
Remove-NetFirewallRule -DisplayName "Lab4-Allow-SSH-Host" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "Lab4-Block-ICMP-Host" -ErrorAction SilentlyContinue
Enable-NetFirewallRule -DisplayGroup "File and Printer Sharing" -Direction Inbound -ErrorAction SilentlyContinue
Write-Host "Firewall OFF: Custom rules removed. Default ICMP echo rule enabled (ping allowed)." -ForegroundColor Green
'@

$fwonScript | Out-File -FilePath $fwonPath -Encoding utf8 -Force
$fwoffScript | Out-File -FilePath $fwoffPath -Encoding utf8 -Force

$fwonCmd = "C:\Windows\fwon.cmd"
$fwoffCmd = "C:\Windows\fwoff.cmd"
Remove-Item -Path $fwonCmd -Force -ErrorAction SilentlyContinue
Remove-Item -Path $fwoffCmd -Force -ErrorAction SilentlyContinue

"@echo off`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$fwonPath`"" | Out-File -FilePath $fwonCmd -Encoding ascii
"@echo off`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$fwoffPath`"" | Out-File -FilePath $fwoffCmd -Encoding ascii

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "  GATEWAY SETUP COMPLETE" -ForegroundColor Green
Write-Host "  - External : $externalIf (DHCP)" -ForegroundColor Green
Write-Host "  - Internal : $internalIf = 192.168.99.1/29" -ForegroundColor Green
if ((Get-Service RemoteAccess -ErrorAction SilentlyContinue).Status -ne 'Running') {
    Write-Host "  - [REBOOT RECOMMENDED] Restart Gateway VM for NAT to function." -ForegroundColor Red
}
Write-Host "  - Commands 'fwon' / 'fwoff' now available (persistent firewall toggle)." -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Cyan
