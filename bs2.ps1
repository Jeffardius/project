#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "  Relay DHCP Lease Auto-Wipe Setup" -ForegroundColor Cyan
Write-Host "  Clears all DHCP leases on boot and shutdown" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

# ---------- Configuration ----------
$scopeId = "192.168.99.80"               # Your Node DHCP scope
$scriptDir = "C:\Lab4"
$cleanupScript = "$scriptDir\Clear-DHCPLeases.ps1"
$logFile = "$scriptDir\dhcp_cleanup.log"

# ---------- 1. Create the cleanup script ----------
if (-not (Test-Path $scriptDir)) {
    New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null
}

$cleanupScriptContent = @"
# Clear-DHCPLeases.ps1
`$ErrorActionPreference = "Stop"
`$scopeId = "$scopeId"

# Remove all active leases from the Node scope
Get-DhcpServerv4Lease -ScopeId `$scopeId -ErrorAction SilentlyContinue | 
    Remove-DhcpServerv4Lease -Force

# Log the event
`$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
"`$timestamp: All DHCP leases removed from scope `$scopeId" | Out-File -Append "$logFile"
"@

Set-Content -Path $cleanupScript -Value $cleanupScriptContent -Force
Write-Host "[OK] Cleanup script created at $cleanupScript" -ForegroundColor Green

# ---------- 2. Create scheduled tasks ----------
# Helper function to remove existing task if present
function Remove-TaskIfExists {
    param([string]$TaskName)
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "[INFO] Removed existing scheduled task: $TaskName" -ForegroundColor Yellow
    }
}

# Task 1: At system startup (trigger: AtStartup)
$taskNameStartup = "Relay_Clear_DHCP_Leases_Startup"
Remove-TaskIfExists -TaskName $taskNameStartup

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$cleanupScript`""
$triggerStartup = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

Register-ScheduledTask -TaskName $taskNameStartup `
    -Action $action `
    -Trigger $triggerStartup `
    -Principal $principal `
    -Settings $settings `
    -Force | Out-Null

Write-Host "[OK] Scheduled task '$taskNameStartup' created (runs at boot)" -ForegroundColor Green

# Task 2: At shutdown (trigger: on event 1074 from User32)
$taskNameShutdown = "Relay_Clear_DHCP_Leases_Shutdown"
Remove-TaskIfExists -TaskName $taskNameShutdown

$triggerShutdown = New-ScheduledTaskTrigger -AtShutdown
# Note: -AtShutdown trigger exists only on some Windows versions.
# If it fails, we fall back to event-based trigger.
if (-not $triggerShutdown) {
    $triggerShutdown = New-ScheduledTaskTrigger -EventLog System -EventId 1074 -Source User32
}

Register-ScheduledTask -TaskName $taskNameShutdown `
    -Action $action `
    -Trigger $triggerShutdown `
    -Principal $principal `
    -Settings $settings `
    -Force | Out-Null

Write-Host "[OK] Scheduled task '$taskNameShutdown' created (runs at shutdown)" -ForegroundColor Green

# ---------- 3. Optional: Enable conflict detection (1 ping) ----------
try {
    $current = Get-DhcpServerv4Server -ErrorAction SilentlyContinue
    if ($current.ConflictDetectionAttempts -lt 1) {
        Set-DhcpServerv4Server -ConflictDetectionAttempts 1
        Write-Host "[OK] DHCP conflict detection set to 1 ping (prevents duplicate IPs)" -ForegroundColor Green
    } else {
        Write-Host "[INFO] DHCP conflict detection already enabled" -ForegroundColor Cyan
    }
} catch {
    Write-Host "[WARN] Could not set conflict detection – DHCP server may need a restart" -ForegroundColor Yellow
}

# ---------- 4. Test-run the cleanup script immediately (optional) ----------
Write-Host "`n[ACTION] Running cleanup script now to clear existing leases..." -ForegroundColor Yellow
& $cleanupScript
Write-Host "[OK] Current leases cleared. Node can now obtain 192.168.99.82 on next renew." -ForegroundColor Green

Write-Host "`n=========================================================" -ForegroundColor Cyan
Write-Host "  SETUP COMPLETE" -ForegroundColor Green
Write-Host "  - Leases will be wiped automatically at every boot and shutdown" -ForegroundColor Green
Write-Host "  - Log file: $logFile" -ForegroundColor Green
Write-Host "  - To force Node to get its IP now, run on Node VM:" -ForegroundColor Yellow
Write-Host "        ipconfig /release && ipconfig /renew" -ForegroundColor White
Write-Host "=========================================================" -ForegroundColor Cyan
