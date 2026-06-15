# Diagnostic Script
Write-Host "=== Gateway Firewall Diagnostic ===" -ForegroundColor Cyan
Write-Host "1. Checking active firewall profile..."
Get-NetConnectionProfile

Write-Host "`n2. Checking all ICMP-related rules (Enabled and Disabled)..."
Get-NetFirewallRule | Where-Object {$_.DisplayName -like "*ICMP*" -or $_.DisplayName -like "*Echo Request*"} | Format-Table DisplayName, Enabled, Profile, Action -AutoSize

Write-Host "`n3. Checking 'File and Printer Sharing (Echo Request - ICMPv4-In)' details..."
Get-NetFirewallRule -DisplayName "File and Printer Sharing (Echo Request - ICMPv4-In)" | Format-List *

Write-Host "`n4. Checking all Custom 'Lab' rules..."
Get-NetFirewallRule -DisplayName "Lab*" | Format-List DisplayName, Enabled, Action, Direction, Description

Write-Host "`n5. Checking Network Location Awareness (NLA) Service Status..."
Get-Service NlaSvc

Write-Host "=== Diagnostic Complete ===" -ForegroundColor Cyan
