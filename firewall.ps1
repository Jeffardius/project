#Requires -RunAsAdministrator
Write-Host "=== Hardened Firewall Setup ===" -ForegroundColor Cyan

# ---------- Ensure firewall is enabled on all profiles ----------
Set-NetFirewallProfile -All -Enabled True
Write-Host "Firewall enabled on all profiles." -ForegroundColor Green

# ---------- Get or save Host IP ----------
$hostIPFile = "C:\Lab4_HostIP.txt"
$defaultIP = if (Test-Path $hostIPFile) { Get-Content $hostIPFile -Raw | ForEach-Object { $_.Trim() } }
$prompt = if ($defaultIP) { "Enter Host IP (default: $defaultIP): " } else { "Enter Host IP: " }
$HostIP = Read-Host $prompt
if (-not $HostIP -and $defaultIP) { $HostIP = $defaultIP }
if (-not $HostIP) { Write-Host "No IP provided. Exiting."; exit 1 }
$HostIP | Out-File -FilePath $hostIPFile -Force

# ---------- Remove all custom rules (to start fresh) ----------
netsh advfirewall firewall delete rule name="Lab_Allow_SSH" > $null 2>&1
netsh advfirewall firewall delete rule name="Lab_Block_Ping" > $null 2>&1

# ---------- Disable ALL built-in inbound ICMPv4 Echo Request rules ----------
$icmpRules = @(
    "File and Printer Sharing (Echo Request - ICMPv4-In)",
    "Core Networking Diagnostics - ICMP Echo Request (ICMPv4-In)"
)
foreach ($rule in $icmpRules) {
    Set-NetFirewallRule -DisplayName $rule -Enabled False -ErrorAction SilentlyContinue
}
Write-Host "Built-in ICMPv4 Echo Request rules disabled." -ForegroundColor Green

# ---------- Create allow rule for SSH from Host IP ----------
netsh advfirewall firewall add rule name="Lab_Allow_SSH" dir=in protocol=tcp localport=22 remoteip=$HostIP action=allow
Write-Host "SSH (TCP 22) allowed from $HostIP." -ForegroundColor Green

# ---------- Create block rule for ICMPv4 Echo Request from Host IP ----------
# Using netsh with a specific ICMP type
netsh advfirewall firewall add rule name="Lab_Block_Ping" dir=in protocol=icmpv4:8,any remoteip=$HostIP action=block
Write-Host "ICMPv4 Echo Request (ping) blocked from $HostIP." -ForegroundColor Green

# ---------- Verify rules are active ----------
Write-Host "`nActive firewall rules (custom):" -ForegroundColor Yellow
netsh advfirewall firewall show rule name="Lab_Allow_SSH" | Select-String "RemoteIP|Enabled|Action"
netsh advfirewall firewall show rule name="Lab_Block_Ping" | Select-String "RemoteIP|Enabled|Action"

Write-Host "`n=== Done ===" -ForegroundColor Green
Write-Host "Test: From your host (IP $HostIP), try to ping the Gateway. It should fail." -ForegroundColor Cyan
Write-Host "Test: SSH from your host to the Gateway should succeed." -ForegroundColor Cyan
