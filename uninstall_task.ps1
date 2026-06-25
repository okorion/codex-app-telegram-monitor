$ErrorActionPreference = "Stop"

$taskName = "Ensure Codex App Running at 9AM"
$taskPath = "\Codex\"

$task = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue
if ($task) {
    Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false
    "Removed scheduled task: $taskPath$taskName"
} else {
    "Scheduled task not found: $taskPath$taskName"
}
