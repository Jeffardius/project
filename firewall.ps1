#Requires -RunAsAdministrator

Write-Host "=== Gateway Firewall Fix: Allow Ping + SSH from Host ===" -ForegroundColor Cyan

# ---------- 1. Remove all old custom rules ----------
Write-Host "Removing old custom rules..." -ForegroundColor Yellow
Get-NetFirewallRule -DisplayName "Lab-*" -ErrorAction SilentlyContinue | Remove-NetFirewallRule
netsh advfirewall firewall delete rule name="Lab_Allow_SSH" > $null 2>&1
netsh advfirewall firewall delete rule name="Lab_Block_Ping" > $null 2>&1
netsh advfirewall firewall delete rule name="Block_All_Ping" > $null 2>&1
netsh advfirewall firewall delete rule name="Allow_SSH_from_Host" > $null 2>&1
netsh advfirewall firewall delete rule name="Allow_Ping_from_Host" > $null 2>&1
Write-Host "Old rules removed." -ForegroundColor Green

# ---------- 2. Ensure firewall is enabled (but not overly restrictive) ----------
Set-NetFirewallProfile -All -Enabled True

# ---------- 3. Re-enable built-in ICMP Echo Request rules (in case they were disabled) ----------
$icmpRules = @(
    "File and Printer Sharing (Echo Request - ICMPv4-In)",
    "Core Networking Diagnostics - ICMP Echo Request (ICMPv4-In)"
)
foreach ($rule in $icmpRules) {
    Set-NetFirewallRule -DisplayName $rule -Enabled True -ErrorAction SilentlyContinue
}
Write-Host "Built-in ICMP Echo Request rules re-enabled (as fallback)." -ForegroundColor Green

# ---------- 4. Get (or ask for) Host IP ----------
$hostIPFile = "C:\Lab4_HostIP.txt"
$defaultIP = if (Test-Path $hostIPFile) { Get-Content $hostIPFile -Raw | ForEach-Object { $_.Trim() } }
$prompt = if ($defaultIP) { "Enter Host IP (default: $defaultIP): " } else { "Enter Host IP: " }
$HostIP = Read-Host $prompt
if (-not $HostIP -and $defaultIP) { $HostIP = $defaultIP }
if (-not $HostIP) { Write-Host "No IP provided. Exiting."; exit 1 }
$HostIP | Out-File -FilePath $hostIPFile -Force

# ---------- 5. Create ALLOW rule for SSH (TCP port 22) from Host IP ----------
netsh advfirewall firewall add rule name="Lab_Allow_SSH" dir=in protocol=tcp localport=22 remoteip=$HostIP action=allow
Write-Host "SSH (TCP 22) allowed from $HostIP." -ForegroundColor Green

# ---------- 6. Create ALLOW rule for Ping (ICMP Echo Request) from Host IP ----------
netsh advfirewall firewall add rule name="Lab_Allow_Ping" dir=in protocol=icmpv4:8,any remoteip=$HostIP action=allow
Write-Host "ICMPv4 Echo Request (ping) allowed from $HostIP." -ForegroundColor Green

# ---------- 7. Verify rules ----------
Write-Host "`n=== Active custom rules ===" -ForegroundColor Cyan
netsh advfirewall firewall show rule name="Lab_Allow_SSH" | Select-String "Enabled|RemoteIP|Action"
netsh advfirewall firewall show rule name="Lab_Allow_Ping" | Select-String "Enabled|RemoteIP|Action"

# ---------- 8. Final testing instructions ----------
Write-Host "`n=== Done ===" -ForegroundColor Green
Write-Host "Now test from your HOST machine:" -ForegroundColor Yellow
Write-Host "  - ping <Gateway-IP>           (should SUCCEED)" -ForegroundColor White
Write-Host "  - ssh Administrator@<Gateway-IP>   (should SUCCEED)" -ForegroundColor White
Write-Host "`nIf ping still fails, also check:" -ForegroundColor Cyan
Write-Host "  - That the gateway's network adapter is set to 'Bridged' (not NAT)."
Write-Host "  - That the host and gateway are on the same subnet."
Write-Host "  - That no third-party firewall (e.g., VirtualBox host‑only network) is interfering."
