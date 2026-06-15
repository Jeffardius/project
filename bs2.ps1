#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

# Create cleanup script
$scriptDir = "C:\Lab4"
$cleanupScript = "$scriptDir\Clear-DHCPLeases.ps1"
$scopeId = "192.168.99.80"

if (-not (Test-Path $scriptDir)) { mkdir $scriptDir -Force | Out-Null }

@"
`$ErrorActionPreference = "Stop"
Get-DhcpServerv4Lease -ScopeId "$scopeId" -ErrorAction SilentlyContinue | Remove-DhcpServerv4Lease -Force
"@ | Out-File -FilePath $cleanupScript -Force

# Create startup task (overwrite if exists with /f)
schtasks /create /tn "Relay_Clear_DHCP_Leases_Startup" /tr "powershell.exe -ExecutionPolicy Bypass -File `"$cleanupScript`"" /sc onstart /ru SYSTEM /rl HIGHEST /f

# Create shutdown task (using event 1074, overwrite with /f)
schtasks /create /tn "Relay_Clear_DHCP_Leases_Shutdown" /tr "powershell.exe -ExecutionPolicy Bypass -File `"$cleanupScript`"" /sc onevent /ec System /mo "*[System/EventID=1074]" /ru SYSTEM /rl HIGHEST /f

Write-Host "Done. DHCP leases will be wiped on every boot and shutdown."
