$ErrorActionPreference = "Stop"

$taskName = "Codex Telegram Command Listener"
$taskPath = "\Codex\"
$scriptPath = Join-Path $PSScriptRoot "codex-telegram-command-listener.ps1"
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
$principal = New-ScheduledTaskPrincipal `
    -UserId "$env:USERDOMAIN\$env:USERNAME" `
    -LogonType Interactive `
    -RunLevel Limited
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

$task = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath
$info = Get-ScheduledTaskInfo -TaskName $taskName -TaskPath $taskPath
if ($task.State -ne "Running") {
    Start-ScheduledTask -TaskName $taskName -TaskPath $taskPath
    Start-Sleep -Seconds 2
    $task = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath
    $info = Get-ScheduledTaskInfo -TaskName $taskName -TaskPath $taskPath
}

[PSCustomObject]@{
    TaskName = $task.TaskName
    TaskPath = $task.TaskPath
    State = $task.State
    LastRunTime = $info.LastRunTime
    LastTaskResult = $info.LastTaskResult
    EnvFile = $envFile
} | Format-List
