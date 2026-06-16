# fwon.ps1 - Block ping (ICMPv4 echo request) from a specific IP, allow SSH (port 22) from same IP.
# Run as Administrator.

$ErrorActionPreference = "Stop"

# Read or prompt for host IP
$ipFile = "$env:USERPROFILE\host_ip.txt"
if (Test-Path $ipFile) {
    $default = Get-Content $ipFile -Raw | ForEach-Object { $_.Trim() }
    $prompt = "Enter host IP (default: $default): "
} else { $default = $null; $prompt = "Enter host IP: " }
$hostIP = Read-Host $prompt
if (-not $hostIP -and $default) { $hostIP = $default }
if (-not $hostIP) { Write-Host "No IP provided. Exiting."; exit 1 }
$hostIP | Out-File -FilePath $ipFile -Force

# Remove any existing rules with these names (from previous runs)
netsh advfirewall firewall delete rule name="BlockPingFromHost" > $null 2>&1
netsh advfirewall firewall delete rule name="AllowSSHFromHost" > $null 2>&1
netsh advfirewall firewall delete rule name="Lab_Block_Ping" > $null 2>&1
netsh advfirewall firewall delete rule name="Lab_Allow_SSH" > $null 2>&1

# Disable the built‑in ICMP echo request rules (to avoid them overriding our block)
netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=No > $null 2>&1
netsh advfirewall firewall set rule name="Core Networking Diagnostics - ICMP Echo Request (ICMPv4-In)" new enable=No > $null 2>&1

# Block ping (ICMPv4 type 8) from the host IP
netsh advfirewall firewall add rule name="BlockPingFromHost" dir=in protocol=icmpv4:8,any remoteip=$hostIP action=block

# Allow SSH (TCP port 22) from the host IP
netsh advfirewall firewall add rule name="AllowSSHFromHost" dir=in protocol=tcp localport=22 remoteip=$hostIP action=allow

Write-Host "Done. Ping from $hostIP is blocked; SSH (port 22) allowed."
Write-Host "These rules persist across reboots. Run fwoff to undo."
