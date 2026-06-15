# fw_hardened.ps1
Write-Host "Applying Hardened Firewall Rules..." -ForegroundColor Yellow

$hostIPFile = "C:\Lab4_HostIP.txt"
$defaultIP = $null

# Get Host IP (with default)
if (Test-Path $hostIPFile) {
    $defaultIP = Get-Content $hostIPFile -Raw | ForEach-Object { $_.Trim() }
    $prompt = "Enter Host IP (default: $defaultIP): "
} else {
    $prompt = "Enter Host IP: "
}
$HostIP = Read-Host $prompt
if ([string]::IsNullOrWhiteSpace($HostIP) -and $defaultIP) {
    $HostIP = $defaultIP
    Write-Host "Using saved IP: $HostIP"
} elseif ([string]::IsNullOrWhiteSpace($HostIP)) {
    Write-Host "No IP provided. Exiting."; exit 1
}
$HostIP | Out-File -FilePath $hostIPFile -Force

# 1. Create a DENY rule for ALL ICMPv4 traffic from ANY source.
#    This is a very aggressive block that takes top priority.
netsh advfirewall firewall add rule name="Block_All_Ping" dir=in protocol=icmpv4:8,any action=block

# 2. Create an ALLOW rule for SSH (TCP port 22) from your specific host IP.
#    The "security" profile is the most generic, helping it apply correctly.
netsh advfirewall firewall add rule name="Allow_SSH_from_Host" dir=in protocol=tcp localport=22 remoteip=$HostIP action=allow

Write-Host "`nHardened rules applied. Attempting to ping Gateway from Host..." -ForegroundColor Green

# 3. Display the newly created rules for verification
netsh advfirewall firewall show rule name="Block_All_Ping"
netsh advfirewall firewall show rule name="Allow_SSH_from_Host"
