$ErrorActionPreference = "Stop"

$taskName = "Codex Telegram Command Listener"
$watchdogTaskName = "Codex Telegram Command Listener Watchdog"
$taskPath = "\Codex\"
$scriptPath = Join-Path $PSScriptRoot "codex-telegram-command-listener.ps1"
$watchdogScriptPath = Join-Path $PSScriptRoot "ensure_command_listener_running.ps1"
$envFile = Join-Path $PSScriptRoot ".env"

if (!(Test-Path -LiteralPath $envFile)) {
    throw "Codex Telegram .env is missing. Run configure-codex-telegram.ps1 first."
}

powershell.exe `
    -NoProfile `
    -ExecutionPolicy Bypass `
    -File $scriptPath `
    -EnvFile $envFile `
    -InitializeOffset

$principal = New-ScheduledTaskPrincipal `
    -UserId "$env:USERDOMAIN\$env:USERNAME" `
    -LogonType Interactive `
    -RunLevel Limited

$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`" -EnvFile `"$envFile`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$settings = New-ScheduledTaskSettingsSet `
    -Hidden `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1)
$description = "Listen for authorized Telegram commands and start the Codex app on this PC when requested."

Register-ScheduledTask `
    -TaskName $taskName `
    -TaskPath $taskPath `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description $description `
    -Force | Out-Null

$watchdogAction = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$watchdogScriptPath`" -EnvFile `"$envFile`""
$watchdogTrigger = New-ScheduledTaskTrigger `
    -Once `
    -At (Get-Date).AddMinutes(1) `
    -RepetitionInterval (New-TimeSpan -Minutes 5) `
    -RepetitionDuration (New-TimeSpan -Days 3650)
$watchdogSettings = New-ScheduledTaskSettingsSet `
    -Hidden `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 2) `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable
$watchdogDescription = "Every 5 minutes, start the Codex Telegram command listener if it is not running."

Register-ScheduledTask `
    -TaskName $watchdogTaskName `
    -TaskPath $taskPath `
    -Action $watchdogAction `
    -Trigger $watchdogTrigger `
    -Settings $watchdogSettings `
    -Principal $principal `
    -Description $watchdogDescription `
    -Force | Out-Null

$task = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath
$info = Get-ScheduledTaskInfo -TaskName $taskName -TaskPath $taskPath
if ($task.State -ne "Running") {
    Start-ScheduledTask -TaskName $taskName -TaskPath $taskPath
    Start-Sleep -Seconds 2
    $task = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath
    $info = Get-ScheduledTaskInfo -TaskName $taskName -TaskPath $taskPath
}

$watchdogTask = Get-ScheduledTask -TaskName $watchdogTaskName -TaskPath $taskPath
$watchdogInfo = Get-ScheduledTaskInfo -TaskName $watchdogTaskName -TaskPath $taskPath

[PSCustomObject]@{
    TaskName = $task.TaskName
    TaskPath = $task.TaskPath
    State = $task.State
    LastRunTime = $info.LastRunTime
    LastTaskResult = $info.LastTaskResult
    WatchdogTaskName = $watchdogTask.TaskName
    WatchdogState = $watchdogTask.State
    WatchdogNextRunTime = $watchdogInfo.NextRunTime
    EnvFile = $envFile
} | Format-List
