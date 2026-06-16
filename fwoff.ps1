# fwoff.ps1 - Remove all custom rules created by fwon and restore default ICMP behaviour.
# Run as Administrator.

$ErrorActionPreference = "Stop"

# Delete all known custom rules (by name patterns)
$ruleNames = @(
    "BlockPingFromHost",
    "AllowSSHFromHost",
    "Lab_Block_Ping",
    "Lab_Allow_SSH",
    "Lab-Block-ICMP-Host",
    "Lab-Allow-SSH-Host",
    "Lab-Block-All-Other-Host",
    "Block_All_Ping",
    "Allow_SSH_from_Host"
)
foreach ($name in $ruleNames) {
    netsh advfirewall firewall delete rule name="$name" > $null 2>&1
}

# Also remove any PowerShell rules with "Lab-" prefix (just in case)
Get-NetFirewallRule -DisplayName "Lab-*" | Remove-NetFirewallRule -ErrorAction SilentlyContinue

# Re-enable the built-in ICMP echo request rules
netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes > $null 2>&1
netsh advfirewall firewall set rule name="Core Networking Diagnostics - ICMP Echo Request (ICMPv4-In)" new enable=Yes > $null 2>&1

Write-Host "Done. All custom rules removed. Ping should now work (default behaviour)."
