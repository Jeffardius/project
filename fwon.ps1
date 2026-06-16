# fwon.ps1 - Block ping from a specific host IP, allow SSH (port 22) from that IP.
# Requires Administrator.
$ErrorActionPreference = "Stop"

# Get the host IP (saved or prompt)
$ipFile = "$env:USERPROFILE\host_ip.txt"
if (Test-Path $ipFile) {
    $defaultIP = Get-Content $ipFile -Raw | ForEach-Object { $_.Trim() }
    $prompt = "Enter host IP (default: $defaultIP): "
} else {
    $defaultIP = $null
    $prompt = "Enter host IP: "
}
$hostIP = Read-Host $prompt
if (-not $hostIP -and $defaultIP) { $hostIP = $defaultIP }
if (-not $hostIP) { Write-Host "No IP provided. Exiting."; exit 1 }
$hostIP | Out-File -FilePath $ipFile -Force

# Delete any existing rules we might have created earlier
netsh advfirewall firewall delete rule name="BlockPingFromHost" > $null 2>&1
netsh advfirewall firewall delete rule name="AllowSSHFromHost" > $null 2>&1

# Disable the built-in ICMP echo request rules (to avoid conflicts)
netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=No > $null 2>&1
netsh advfirewall firewall set rule name="Core Networking Diagnostics - ICMP Echo Request (ICMPv4-In)" new enable=No > $null 2>&1

# Add block rule for ICMPv4 Echo Request (ping) from the host IP
netsh advfirewall firewall add rule name="BlockPingFromHost" dir=in protocol=icmpv4:8,any remoteip=$hostIP action=block

# Add allow rule for SSH (TCP port 22) from the host IP
netsh advfirewall firewall add rule name="AllowSSHFromHost" dir=in protocol=tcp localport=22 remoteip=$hostIP action=allow

Write-Host "Done. Ping from $hostIP is now blocked, SSH (port 22) is allowed."
Write-Host "These rules will survive reboots. Run fwoff.ps1 to undo."
