#Requires -RunAsAdministrator

Write-Host "=== NUCLEAR PING UNBLOCK ===" -ForegroundColor Red

# 1. Disable firewall completely (all profiles)
Write-Host "Disabling Windows Firewall on all profiles..." -ForegroundColor Yellow
Set-NetFirewallProfile -All -Enabled False
netsh advfirewall set allprofiles state off

# 2. Stop the firewall service (so it can't interfere)
Write-Host "Stopping firewall service..." -ForegroundColor Yellow
Stop-Service mpssvc -Force -ErrorAction SilentlyContinue
Set-Service mpssvc -StartupType Disabled

# 3. Remove all custom rules that might block ICMP
Write-Host "Removing any rule that mentions ICMP or ping..." -ForegroundColor Yellow
Get-NetFirewallRule | Where-Object { $_.DisplayName -match "ICMP|Ping|Echo" } | Remove-NetFirewallRule -ErrorAction SilentlyContinue
netsh advfirewall firewall delete rule name="all" protocol=icmpv4 > $null 2>&1

# 4. Add an explicit allow rule for all ICMP (any source, any destination)
Write-Host "Adding explicit allow rule for all ICMPv4..." -ForegroundColor Yellow
netsh advfirewall firewall add rule name="Allow_ALL_ICMPv4" dir=in protocol=icmpv4 action=allow

# 5. If still blocking, check for persistent filters via WFP (netsh wfp)
Write-Host "Resetting Windows Filtering Platform (WFP)..." -ForegroundColor Yellow
netsh wfp reset

# 6. Set network profile to Private (less restrictive)
Write-Host "Setting network profile to Private..." -ForegroundColor Yellow
Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private -ErrorAction SilentlyContinue

# 7. Restart the network adapter to apply changes
Write-Host "Restarting network adapter..." -ForegroundColor Yellow
$adapter = Get-NetAdapter -Name "Ethernet" -ErrorAction SilentlyContinue
if ($adapter) {
    Restart-NetAdapter -Name $adapter.Name -Confirm:$false
    Start-Sleep -Seconds 3
}

Write-Host "`n=== PING SHOULD NOW WORK ===" -ForegroundColor Green
Write-Host "Test from your host: ping <Gateway-IP>" -ForegroundColor Cyan
Write-Host "If it still fails, reboot the VM (required for some changes)." -ForegroundColor Yellow

$reboot = Read-Host "Reboot now? (Y/N)"
if ($reboot -eq 'Y' -or $reboot -eq 'y') {
    Restart-Computer -Force
}
