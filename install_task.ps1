$ErrorActionPreference = "Stop"

$taskName = "Ensure Codex App Running at 9AM"
$taskPath = "\Codex\"
$scriptPath = Join-Path $PSScriptRoot "ensure-codex-app-with-telegram.ps1"
$envFile = Join-Path $PSScriptRoot ".env"

if (!(Test-Path -LiteralPath $envFile)) {
    throw "Codex Telegram .env is missing. Run configure-codex-telegram.ps1 first."
}

$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`" -EnvFile `"$envFile`""
$trigger = New-ScheduledTaskTrigger -Daily -At 9:00AM
$settings = New-ScheduledTaskSettingsSet `
    -Hidden `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable
$principal = New-ScheduledTaskPrincipal `
    -UserId "$env:USERDOMAIN\$env:USERNAME" `
    -LogonType Interactive `
    -RunLevel Limited
$description = "At 09:00 daily, start the Codex app if needed and send the check result to the dedicated Codex Telegram bot."

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

[PSCustomObject]@{
    TaskName = $task.TaskName
    TaskPath = $task.TaskPath
    State = $task.State
    NextRunTime = $info.NextRunTime
    EnvFile = $envFile
} | Format-List
