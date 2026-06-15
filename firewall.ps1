#Requires -RunAsAdministrator
Write-Host "=== Final Firewall Fix (SSH allowed, ping blocked) ===" -ForegroundColor Cyan

# ---------- 1. Remove all custom rules (PowerShell and netsh) ----------
Write-Host "Removing old custom rules..." -ForegroundColor Yellow

# Remove PowerShell rules (Lab-*)
Get-NetFirewallRule -DisplayName "Lab-*" -ErrorAction SilentlyContinue | Remove-NetFirewallRule
# Remove netsh rules (Lab_*)
netsh advfirewall firewall delete rule name="Lab_Allow_SSH" > $null 2>&1
netsh advfirewall firewall delete rule name="Lab_Block_Ping" > $null 2>&1
# Also remove any other possible custom rules from previous attempts
netsh advfirewall firewall delete rule name="Block_All_Ping" > $null 2>&1
netsh advfirewall firewall delete rule name="Allow_SSH_from_Host" > $null 2>&1

Write-Host "Old rules removed." -ForegroundColor Green

# ---------- 2. Ensure firewall is enabled on all profiles ----------
Set-NetFirewallProfile -All -Enabled True

# ---------- 3. Disable built‑in ICMPv4 Echo Request rules ----------
$icmpRules = @(
    "File and Printer Sharing (Echo Request - ICMPv4-In)",
    "Core Networking Diagnostics - ICMP Echo Request (ICMPv4-In)"
)
foreach ($rule in $icmpRules) {
    Set-NetFirewallRule -DisplayName $rule -Enabled False -ErrorAction SilentlyContinue
}
Write-Host "Built-in ICMP Echo Request rules disabled." -ForegroundColor Green

# ---------- 4. Get (or ask for) Host IP ----------
$hostIPFile = "C:\Lab4_HostIP.txt"
$defaultIP = if (Test-Path $hostIPFile) { Get-Content $hostIPFile -Raw | ForEach-Object { $_.Trim() } }
$prompt = if ($defaultIP) { "Enter Host IP (default: $defaultIP): " } else { "Enter Host IP: " }
$HostIP = Read-Host $prompt
if (-not $HostIP -and $defaultIP) { $HostIP = $defaultIP }
if (-not $HostIP) { Write-Host "No IP provided. Exiting."; exit 1 }
$HostIP | Out-File -FilePath $hostIPFile -Force

# ---------- 5. Create SSH allow rule (TCP 22) from Host IP ----------
netsh advfirewall firewall add rule name="Lab_Allow_SSH" dir=in protocol=tcp localport=22 remoteip=$HostIP action=allow
Write-Host "SSH (TCP 22) allowed from $HostIP." -ForegroundColor Green

# ---------- 6. Create ICMP block rule (ping) from Host IP ----------
netsh advfirewall firewall add rule name="Lab_Block_Ping" dir=in protocol=icmpv4:8,any remoteip=$HostIP action=block
Write-Host "ICMPv4 Echo Request (ping) blocked from $HostIP." -ForegroundColor Green

# ---------- 7. Verify rules ----------
Write-Host "`n=== Active custom rules ===" -ForegroundColor Cyan
netsh advfirewall firewall show rule name="Lab_Allow_SSH" | Select-String "Enabled|RemoteIP|Action"
netsh advfirewall firewall show rule name="Lab_Block_Ping" | Select-String "Enabled|RemoteIP|Action"

Write-Host "`n=== Done ===" -ForegroundColor Green
Write-Host "Now test:" -ForegroundColor Yellow
Write-Host "  - ping <Gateway-IP>  (should fail/timeout)" -ForegroundColor White
Write-Host "  - ssh Administrator@<Gateway-IP>  (should succeed)" -ForegroundColor White
