#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Registers update.ps1 as a Windows Task Scheduler job that runs at every logon.
.NOTES
    Run this script once as Administrator.
#>

# ============================================================
#  Adjust path to match where you placed update.ps1
# ============================================================
$ScriptPath = "C:\Tools\github-updater\update.ps1"
$TaskName   = "GitHubAutoUpdater"
# ============================================================

$action  = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ScriptPath`""

# Runs for every user that logs on; change to a specific user if preferred
$trigger = New-ScheduledTaskTrigger -AtLogOn

$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10) `
    -RestartCount 2 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -StartWhenAvailable

# Run with highest privileges so it can write to system paths if needed
$principal = New-ScheduledTaskPrincipal `
    -UserId "SYSTEM" `
    -LogonType ServiceAccount `
    -RunLevel Highest

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description "Checks GitHub for updates and downloads them automatically." `
    -Force

Write-Host "Task '$TaskName' registered successfully." -ForegroundColor Green
Write-Host "To remove it later run:  Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false"
