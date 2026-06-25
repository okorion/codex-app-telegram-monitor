$ErrorActionPreference = "Stop"

$taskNames = @(
    "Codex Telegram Command Listener",
    "Codex Telegram Command Listener Watchdog"
)
$taskPath = "\Codex\"

foreach ($taskName in $taskNames) {
    $task = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue
    if ($task) {
        Stop-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false
        "Removed scheduled task: $taskPath$taskName"
    } else {
        "Scheduled task not found: $taskPath$taskName"
    }
}
