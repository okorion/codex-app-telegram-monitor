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
        "예약 작업 제거 완료: $taskPath$taskName"
    } else {
        "예약 작업을 찾을 수 없음: $taskPath$taskName"
    }
}
