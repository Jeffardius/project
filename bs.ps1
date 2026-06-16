#Requires -RunAsAdministrator
Write-Host "=== Firewall Diagnostic Script ===" -ForegroundColor Cyan

# 1. Windows Firewall service status
Write-Host "`n[1] Windows Firewall Service:" -ForegroundColor Yellow
Get-Service mpssvc | Format-List Name, Status, StartType

# 2. Firewall profile status (enabled/disabled)
Write-Host "`n[2] Firewall Profile Status (Enabled = filtering is active):" -ForegroundColor Yellow
Get-NetFirewallProfile | Select-Object Name, Enabled

# 3. List all custom rules (names containing "Block" or "Allow" from our scripts)
Write-Host "`n[3] Custom Rules (likely from our scripts):" -ForegroundColor Yellow
Get-NetFirewallRule | Where-Object {
    $_.DisplayName -match "Block|Allow|Lab|Ping|SSH"
} | Format-Table DisplayName, Enabled, Direction, Action, RemoteAddress -AutoSize

# Also check netsh rules (older ones)
Write-Host "`n[4] Netsh advfirewall rules (custom):" -ForegroundColor Yellow
netsh advfirewall firewall show rule name=all | Select-String -Pattern "Rule Name:|Enabled:|RemoteIP:|LocalPort:|Protocol:" -Context 0,0 | Out-String

# 5. Specifically check ICMPv4 Echo Request rules (both built-in and custom)
Write-Host "`n[5] ICMPv4 Echo Request (ping) rules - Inbound:" -ForegroundColor Yellow
Get-NetFirewallRule -Direction Inbound | Where-Object {
    ($_.DisplayName -like "*Echo Request*") -or ($_.DisplayName -like "*ICMP*")
} | Format-Table DisplayName, Enabled, Profile, Action -AutoSize

# 6. Check if any explicit block rules for your host IP (e.g., 10.0.0.66)
Write-Host "`n[6] Rules with RemoteAddress containing your host IP (10.0.0.66):" -ForegroundColor Yellow
Get-NetFirewallRule | ForEach-Object {
    $rule = $_
    $addr = Get-NetFirewallRemoteAddress -PolicyStore $rule.PolicyStoreSource -ErrorAction SilentlyContinue
    if ($addr -and $addr.ToString() -match "10\.0\.0\.66") {
        [PSCustomObject]@{
            Name = $rule.DisplayName
            Enabled = $rule.Enabled
            Action = $rule.Action
            RemoteAddress = $addr.ToString()
        }
    }
} | Format-Table -AutoSize

# 7. Check effective policy (could be overridden by group policy)
Write-Host "`n[7] Effective Firewall Policy (local or domain):" -ForegroundColor Yellow
Get-NetFirewallRule -PolicyStore ActiveStore | Where-Object {
    $_.DisplayName -match "Echo|ICMP|Ping|SSH|Block|Allow"
} | Select-Object -First 20 | Format-Table DisplayName, Enabled, Action, Direction -AutoSize

# 8. Check if any other security software is running
Write-Host "`n[8] Other Security Software (antivirus/third-party firewalls):" -ForegroundColor Yellow
Get-Process | Where-Object {
    $_.ProcessName -match "defender|firewall|security|avp|avg|norton|mcafee|symantec"
} | Select-Object ProcessName, Id

# 9. Network interface status and assigned IPs
Write-Host "`n[9] Network Interfaces (relevant):" -ForegroundColor Yellow
Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
    $_.InterfaceAlias -notlike "*Loopback*"
} | Format-Table InterfaceAlias, IPAddress, PrefixLength

Write-Host "`n[10] Last attempt to remove custom rules (simulate fwoff):" -ForegroundColor Yellow
Write-Host "Running cleanup commands from fwoff..."
netsh advfirewall firewall delete rule name="BlockPingFromHost" > $null 2>&1
netsh advfirewall firewall delete rule name="AllowSSHFromHost" > $null 2>&1
netsh advfirewall firewall delete rule name="Lab-Block-ICMP-Host" > $null 2>&1
netsh advfirewall firewall delete rule name="Lab-Allow-SSH-Host" > $null 2>&1
netsh advfirewall firewall delete rule name="Lab-Block-All-Other-Host" > $null 2>&1
netsh advfirewall firewall delete rule name="Block_All_Ping" > $null 2>&1
netsh advfirewall firewall delete rule name="Allow_SSH_from_Host" > $null 2>&1
Get-NetFirewallRule -DisplayName "Lab-*" | Remove-NetFirewallRule -ErrorAction SilentlyContinue
Write-Host "Cleanup attempted. Re-checking custom rules now..." -ForegroundColor Green
Get-NetFirewallRule | Where-Object {
    $_.DisplayName -match "Block|Allow|Lab|Ping|SSH"
} | Format-Table DisplayName, Enabled, Action -AutoSize

Write-Host "`n=== Diagnostic Complete ===" -ForegroundColor Cyan
Write-Host "If ping still fails, check the output for any remaining Block rules." -ForegroundColor Yellow
