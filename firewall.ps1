#Requires -RunAsAdministrator

Write-Host "=== Configure Firewall: Allow SSH, Block Ping ===" -ForegroundColor Cyan

# ---------- 1. Ask for the allowed host IP ----------
$defaultIP = "10.33.28.107"   # change to your host's typical IP or leave as example
$HostIP = Read-Host "Enter the IP address that should be allowed to SSH (e.g., $defaultIP)"
if (-not $HostIP) { $HostIP = $defaultIP }

# ---------- 2. Enable firewall on all profiles ----------
Set-NetFirewallProfile -All -Enabled True
Write-Host "Firewall is ON." -ForegroundColor Green

# ---------- 3. Remove any old custom SSH rules to avoid conflicts ----------
Get-NetFirewallRule -DisplayName "Lab_Allow_SSH" -ErrorAction SilentlyContinue | Remove-NetFirewallRule
Get-NetFirewallRule -DisplayName "Allow_SSH_From_Host" -ErrorAction SilentlyContinue | Remove-NetFirewallRule

# ---------- 4. Add new SSH allow rule (TCP 22) from the specified IP ----------
New-NetFirewallRule -DisplayName "Allow_SSH_From_Host" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 22 `
    -RemoteAddress $HostIP `
    -Action Allow `
    -Profile Any
Write-Host "SSH (TCP/22) allowed from $HostIP." -ForegroundColor Green

# ---------- 5. Ensure ICMP (ping) is blocked ----------
# Remove any custom ICMP allow rules
Get-NetFirewallRule -DisplayName "Allow_ALL_ICMPv4" -ErrorAction SilentlyContinue | Remove-NetFirewallRule
Get-NetFirewallRule -DisplayName "Lab_Allow_Ping" -ErrorAction SilentlyContinue | Remove-NetFirewallRule

# Disable built-in rules that could allow ping
Set-NetFirewallRule -DisplayName "File and Printer Sharing (Echo Request - ICMPv4-In)" -Enabled False -ErrorAction SilentlyContinue
Set-NetFirewallRule -DisplayName "Core Networking Diagnostics - ICMP Echo Request (ICMPv4-In)" -Enabled False -ErrorAction SilentlyContinue
Write-Host "ICMP (ping) is now BLOCKED." -ForegroundColor Yellow

# ---------- 6. Show current status ----------
Write-Host "`n--- Active SSH allow rule ---" -ForegroundColor Cyan
Get-NetFirewallRule -DisplayName "Allow_SSH_From_Host" | Format-List DisplayName, Enabled, Direction, Action

Write-Host "`n--- ICMP inbound rules (should all be disabled or block) ---" -ForegroundColor Cyan
Get-NetFirewallRule | Where-Object { $_.DisplayName -match "ICMP|Echo" -and $_.Direction -eq 'Inbound' } | Format-Table DisplayName, Enabled, Action -AutoSize

Write-Host "`n=== Done ===" -ForegroundColor Green
Write-Host "From your host machine ($HostIP), you can now SSH to this VM." -ForegroundColor White
Write-Host "Ping will be blocked." -ForegroundColor White
