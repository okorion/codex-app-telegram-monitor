param(
    [string]$EnvFile = (Join-Path $PSScriptRoot ".env")
)

$ErrorActionPreference = "Stop"

$taskName = "Codex Telegram Command Listener"
$taskPath = "\Codex\"

$task = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue
if (!$task) {
    throw "Scheduled task not found: $taskPath$taskName"
}

if ($task.State -ne "Running") {
    Start-ScheduledTask -TaskName $taskName -TaskPath $taskPath
    Start-Sleep -Seconds 2
    $task = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath
}

$info = Get-ScheduledTaskInfo -TaskName $taskName -TaskPath $taskPath

[PSCustomObject]@{
    TaskName = $task.TaskName
    TaskPath = $task.TaskPath
    State = $task.State
    LastRunTime = $info.LastRunTime
    LastTaskResult = $info.LastTaskResult
    EnvFile = $EnvFile
} | Format-List
