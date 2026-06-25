param(
    [string]$EnvFile = (Join-Path $PSScriptRoot ".env")
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "codex-monitor-common.ps1")

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$existing = Read-CodexDotEnvKeys -Path $EnvFile

function Get-ExistingValue {
    param([Parameter(Mandatory = $true)][string]$Key, [string]$Default = "")

    if ($existing.ContainsKey($Key)) {
        return $existing[$Key]
    }

    return $Default
}

function Add-Field {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.Form]$Form,
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][int]$Top,
        [string]$Value = "",
        [switch]$Password
    )

    $labelControl = New-Object System.Windows.Forms.Label
    $labelControl.Text = $Label
    $labelControl.Left = 16
    $labelControl.Top = $Top + 4
    $labelControl.Width = 190
    $Form.Controls.Add($labelControl)

    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Left = 210
    $textBox.Top = $Top
    $textBox.Width = 390
    $textBox.Text = $Value
    if ($Password) {
        $textBox.UseSystemPasswordChar = $true
    }
    $Form.Controls.Add($textBox)

    return $textBox
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "Codex App Telegram Monitor 설정"
$form.StartPosition = "CenterScreen"
$form.Width = 640
$form.Height = 430
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$botToken = Add-Field -Form $form -Label "Telegram bot token" -Top 20 -Value (Get-ExistingValue -Key "TELEGRAM_BOT_TOKEN") -Password
$chatId = Add-Field -Form $form -Label "알림 chat ID" -Top 58 -Value (Get-ExistingValue -Key "TELEGRAM_CHAT_ID")
$personalChatId = Add-Field -Form $form -Label "개인 chat ID" -Top 96 -Value (Get-ExistingValue -Key "TELEGRAM_PERSONAL_CHAT_ID")
$allowedChats = Add-Field -Form $form -Label "알림 허용 채팅" -Top 134 -Value (Get-ExistingValue -Key "TELEGRAM_ALLOWED_CHAT_IDS")
$commandChats = Add-Field -Form $form -Label "명령 허용 채팅" -Top 172 -Value (Get-ExistingValue -Key "TELEGRAM_COMMAND_ALLOWED_CHAT_IDS")
$startChats = Add-Field -Form $form -Label "실행 허용 채팅" -Top 210 -Value (Get-ExistingValue -Key "TELEGRAM_START_ALLOWED_CHAT_IDS")
$deviceName = Add-Field -Form $form -Label "PC 표시 이름" -Top 248 -Value (Get-ExistingValue -Key "CODEX_DEVICE_NAME" -Default "auto")
$title = Add-Field -Form $form -Label "메시지 제목" -Top 286 -Value (Get-ExistingValue -Key "CODEX_MONITOR_TITLE" -Default "Codex app monitor test")

$saveButton = New-Object System.Windows.Forms.Button
$saveButton.Text = ".env 저장"
$saveButton.Left = 210
$saveButton.Top = 330
$saveButton.Width = 110
$form.Controls.Add($saveButton)

$diagnoseButton = New-Object System.Windows.Forms.Button
$diagnoseButton.Text = "진단 실행"
$diagnoseButton.Left = 332
$diagnoseButton.Top = 330
$diagnoseButton.Width = 120
$form.Controls.Add($diagnoseButton)

$closeButton = New-Object System.Windows.Forms.Button
$closeButton.Text = "닫기"
$closeButton.Left = 464
$closeButton.Top = 330
$closeButton.Width = 110
$form.Controls.Add($closeButton)

$saveButton.Add_Click({
    try {
        if ([string]::IsNullOrWhiteSpace($botToken.Text)) {
            throw "Telegram bot token은 필수입니다."
        }
        if ([string]::IsNullOrWhiteSpace($chatId.Text) -and [string]::IsNullOrWhiteSpace($personalChatId.Text)) {
            throw "chat ID가 하나 이상 필요합니다."
        }

        $resolvedPersonalChatId = if ([string]::IsNullOrWhiteSpace($personalChatId.Text)) { $chatId.Text.Trim() } else { $personalChatId.Text.Trim() }
        $resolvedAllowedChats = if ([string]::IsNullOrWhiteSpace($allowedChats.Text)) { $resolvedPersonalChatId } else { $allowedChats.Text.Trim() }
        $resolvedCommandChats = if ([string]::IsNullOrWhiteSpace($commandChats.Text)) { $resolvedAllowedChats } else { $commandChats.Text.Trim() }
        $resolvedStartChats = if ([string]::IsNullOrWhiteSpace($startChats.Text)) { $resolvedCommandChats } else { $startChats.Text.Trim() }

        $lines = @(
            "TELEGRAM_BOT_TOKEN=$($botToken.Text.Trim())",
            "TELEGRAM_CHAT_ID=$($chatId.Text.Trim())",
            "TELEGRAM_PERSONAL_CHAT_ID=$resolvedPersonalChatId",
            "TELEGRAM_ALLOWED_CHAT_IDS=$resolvedAllowedChats",
            "TELEGRAM_COMMAND_ALLOWED_CHAT_IDS=$resolvedCommandChats",
            "TELEGRAM_START_ALLOWED_CHAT_IDS=$resolvedStartChats",
            "CODEX_MONITOR_TITLE=$($title.Text.Trim())",
            "CODEX_DEVICE_NAME=$($deviceName.Text.Trim())",
            "CODEX_APP_USER_MODEL_ID=$(Get-ExistingValue -Key "CODEX_APP_USER_MODEL_ID" -Default "auto")",
            "CODEX_PROCESS_PATH_PATTERN=$(Get-ExistingValue -Key "CODEX_PROCESS_PATH_PATTERN" -Default "auto")",
            "CODEX_LOG_MAX_BYTES=$(Get-ExistingValue -Key "CODEX_LOG_MAX_BYTES" -Default "1048576")",
            "CODEX_LOG_KEEP_FILES=$(Get-ExistingValue -Key "CODEX_LOG_KEEP_FILES" -Default "5")",
            "CODEX_HEARTBEAT_STALE_SECONDS=$(Get-ExistingValue -Key "CODEX_HEARTBEAT_STALE_SECONDS" -Default "120")"
        )

        $envDir = Split-Path -Parent $EnvFile
        if (!(Test-Path -LiteralPath $envDir)) {
            New-Item -ItemType Directory -Path $envDir -Force | Out-Null
        }
        Set-Content -LiteralPath $EnvFile -Encoding UTF8 -Value $lines
        Protect-CodexEnvFile -Path $EnvFile

        [System.Windows.Forms.MessageBox]::Show(".env를 저장하고 ACL을 보호했습니다.", "Codex App Telegram Monitor") | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "저장 실패") | Out-Null
    }
})

$diagnoseButton.Add_Click({
    try {
        Start-Process powershell.exe -ArgumentList @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-NoExit",
            "-File", (Join-Path $PSScriptRoot "diagnose.ps1")
        )
    } catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "진단 실행 실패") | Out-Null
    }
})

$closeButton.Add_Click({
    $form.Close()
})

[void]$form.ShowDialog()
