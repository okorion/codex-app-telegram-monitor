$ErrorActionPreference = "Stop"

$taskName = "Ensure Codex App Running at 9AM"
$taskPath = "\Codex\"
$scriptPath = Join-Path $PSScriptRoot "ensure-codex-app-with-telegram.ps1"
$envFile = Join-Path $PSScriptRoot ".env"

if (!(Test-Path -LiteralPath $envFile)) {
    throw "Codex Telegram .env가 없습니다. configure-codex-telegram.ps1을 먼저 실행하세요."
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
$description = "매일 09:00에 Codex App 상태를 확인하고 필요하면 실행한 뒤 전용 Telegram bot으로 결과를 보냅니다."

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
