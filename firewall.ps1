#Requires -RunAsAdministrator

Write-Host "=== BLOCKING PING ===" -ForegroundColor Red

# 1. Turn firewall ON (required to block anything)
Set-NetFirewallProfile -All -Enabled True
Write-Host "Firewall enabled." -ForegroundColor Green

# 2. Remove any custom allow rule for ICMP (if exists)
Remove-NetFirewallRule -DisplayName "Allow_ALL_ICMPv4" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "Lab_Allow_Ping" -ErrorAction SilentlyContinue

# 3. Disable built-in rules that could allow ping
Set-NetFirewallRule -DisplayName "File and Printer Sharing (Echo Request - ICMPv4-In)" -Enabled False -ErrorAction SilentlyContinue
Set-NetFirewallRule -DisplayName "Core Networking Diagnostics - ICMP Echo Request (ICMPv4-In)" -Enabled False -ErrorAction SilentlyContinue

Write-Host "All ICMP allow rules removed/disabled." -ForegroundColor Green
Write-Host "Ping should now be BLOCKED." -ForegroundColor Yellow

# Optional: show current ICMP rules
Write-Host "`nCurrent ICMPv4 inbound rules:" -ForegroundColor Cyan
Get-NetFirewallRule | Where-Object { $_.DisplayName -match "ICMP|Echo" -and $_.Direction -eq 'Inbound' -and $_.Protocol -eq 'ICMPv4' } | Format-Table DisplayName, Enabled, Action -AutoSize
