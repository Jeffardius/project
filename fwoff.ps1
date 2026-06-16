# fwoff.ps1 - Remove the rules created by fwon.ps1, restore default ICMP behaviour.
# Requires Administrator.
$ErrorActionPreference = "Stop"

# Delete the custom rules
netsh advfirewall firewall delete rule name="BlockPingFromHost" > $null 2>&1
netsh advfirewall firewall delete rule name="AllowSSHFromHost" > $null 2>&1

# Re-enable the built-in ICMP echo request rules (optional but good)
netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes > $null 2>&1
netsh advfirewall firewall set rule name="Core Networking Diagnostics - ICMP Echo Request (ICMPv4-In)" new enable=Yes > $null 2>&1

Write-Host "Done. Ping is now allowed again (default behaviour)."
Write-Host "SSH is no longer specifically allowed from your host; default rules apply."
