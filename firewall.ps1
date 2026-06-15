#Requires -RunAsAdministrator

Write-Host "=== Installing Network Fix Shortcuts ===" -ForegroundColor Cyan

# Choose shortcut location (change to "$env:USERPROFILE\Desktop" if you prefer private)
$shortcutDir = "$env:Public\Desktop"
if (-not (Test-Path $shortcutDir)) { $shortcutDir = "$env:USERPROFILE\Desktop" }

function Create-Shortcut {
    param($Name, $Command, $IconPath = "imageres.dll", $IconIndex = 0)
    $shortcutFile = Join-Path $shortcutDir "$Name.lnk"
    $WScriptShell = New-Object -ComObject WScript.Shell
    $shortcut = $WScriptShell.CreateShortcut($shortcutFile)
    $shortcut.TargetPath = "powershell.exe"
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"$Command`""
    $shortcut.IconLocation = "$IconPath,$IconIndex"
    $shortcut.Save()
    Write-Host "  Created: $Name" -ForegroundColor Green
}

# ---------- Shortcut 1: Disable DAD (fix IP conflicts) ----------
Create-Shortcut -Name "01 - Disable DAD" -Command @"
Write-Host 'Disabling DAD...' -ForegroundColor Cyan;
Get-NetIPInterface -AddressFamily IPv4 | Where-Object {`$_.InterfaceAlias -notlike '*Loopback*'} | ForEach-Object {
    Set-NetIPInterface -InterfaceAlias `$_.InterfaceAlias -AddressFamily IPv4 -DadTransmits 0 -ErrorAction SilentlyContinue;
    Write-Host "  Disabled DAD on `$(`$_.InterfaceAlias)";
};
Write-Host 'Done. Reboot may be required.' -ForegroundColor Green;
Read-Host 'Press Enter to exit'
"@

# ---------- Shortcut 2: Enable Ping (allow ICMP) ----------
Create-Shortcut -Name "02 - Enable Ping" -Command @"
Write-Host 'Enabling ICMP (ping)...' -ForegroundColor Cyan;
netsh advfirewall firewall add rule name='Allow_ALL_ICMPv4' dir=in protocol=icmpv4 action=allow > `$null 2>&1;
Set-NetFirewallRule -DisplayName 'Allow_ALL_ICMPv4' -Enabled True -ErrorAction SilentlyContinue;
Write-Host 'Ping is now allowed.' -ForegroundColor Green;
Read-Host 'Press Enter to exit'
"@

# ---------- Shortcut 3: Disable Ping (block ICMP) ----------
Create-Shortcut -Name "03 - Disable Ping" -Command @"
Write-Host 'Disabling ICMP (ping)...' -ForegroundColor Cyan;
netsh advfirewall firewall delete rule name='Allow_ALL_ICMPv4' > `$null 2>&1;
Write-Host 'Ping is now blocked (firewall default).' -ForegroundColor Green;
Read-Host 'Press Enter to exit'
"@

# ---------- Shortcut 4: Reset Entire Network Stack (fix all) ----------
Create-Shortcut -Name "04 - Reset Network Stack (Reboot)" -Command @"
Write-Host 'Resetting TCP/IP, Winsock, and Firewall...' -ForegroundColor Red;
netsh int ip reset;
netsh winsock reset;
netsh advfirewall reset;
Write-Host 'Network reset complete. Rebooting in 10 seconds...' -ForegroundColor Yellow;
Start-Sleep -Seconds 10;
Restart-Computer -Force
"@

# ---------- Shortcut 5: Firewall OFF (temporarily) ----------
Create-Shortcut -Name "05 - Firewall OFF" -Command @"
Write-Host 'Disabling Windows Firewall...' -ForegroundColor Yellow;
Set-NetFirewallProfile -All -Enabled False;
Write-Host 'Firewall is OFF. Ping and everything allowed.' -ForegroundColor Green;
Read-Host 'Press Enter to exit'
"@

# ---------- Shortcut 6: Firewall ON (with ping allowed if rule present) ----------
Create-Shortcut -Name "06 - Firewall ON" -Command @"
Write-Host 'Enabling Windows Firewall...' -ForegroundColor Yellow;
Set-NetFirewallProfile -All -Enabled True;
Write-Host 'Firewall is ON. (Ping status depends on allow rule)' -ForegroundColor Green;
Read-Host 'Press Enter to exit'
"@

Write-Host "`nAll shortcuts created in: $shortcutDir" -ForegroundColor Cyan
Write-Host "Double-click any shortcut to run the fix (will run as Admin automatically if needed)." -ForegroundColor Yellow
Start-Sleep -Seconds 2
