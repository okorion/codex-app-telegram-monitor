Describe "Codex desktop process detection" {
    BeforeAll {
        . (Join-Path (Split-Path -Parent $PSScriptRoot) "codex-monitor-common.ps1")
    }

    It "recognizes the renamed desktop executable" {
        Test-CodexAppProcessPath -Path 'C:\Program Files\WindowsApps\OpenAI.Codex_26.901_x64__publisher\app\ChatGPT.exe' | Should -Be $true
    }

    It "preserves detection of the original desktop executable" {
        Test-CodexAppProcessPath -Path 'C:\Program Files\WindowsApps\OpenAI.Codex_26.600_x64__publisher\app\Codex.exe' | Should -Be $true
    }

    It "excludes the separate ChatGPT app and Codex CLI" {
        Test-CodexAppProcessPath -Path 'C:\Program Files\WindowsApps\OpenAI.ChatGPT_26.901_x64__publisher\app\ChatGPT.exe' | Should -Be $false
        Test-CodexAppProcessPath -Path 'C:\Program Files\WindowsApps\OpenAI.Codex_26.901_x64__publisher\app\resources\codex.exe' | Should -Be $false
        Test-CodexAppProcessPath -Path 'C:\Local\OpenAI\Codex\bin\revision\codex.exe' | Should -Be $false
        Test-CodexAppProcessPath -Path $null | Should -Be $false
    }

    It "honors an explicit path override without adding automatic matches" {
        Test-CodexAppProcessPath -Path 'D:\Custom\Codex.exe' -ProcessPathPattern 'D:\Custom\*.exe' | Should -Be $true
        Test-CodexAppProcessPath -Path 'C:\Program Files\WindowsApps\OpenAI.Codex_26.901_x64__publisher\app\ChatGPT.exe' -ProcessPathPattern 'D:\Custom\*.exe' | Should -Be $false
    }

    It "does not truncate candidates before filtering and keeps diagnostics consistent" {
        Mock Get-Process {
            1..12 | ForEach-Object { [pscustomobject]@{ Id = $_; Path = 'C:\Other\ChatGPT.exe' } }
            [pscustomobject]@{ Id = 13; Path = 'C:\Program Files\WindowsApps\OpenAI.Codex_26.901_x64__publisher\app\ChatGPT.exe' }
        }
        Mock Get-CodexStartAppCandidates { @() }
        Mock Get-CodexAppxPackageCandidates { @() }

        $processes = @(Get-CodexAppProcesses -ProcessPathPattern auto)
        $processes.Count | Should -Be 1
        $processes[0].Id | Should -Be 13
        $summary = Get-CodexDetectionSummary -ProcessPathPattern auto
        $summary.CodexProcessCount | Should -Be 13
        $summary.MatchingProcessCount | Should -Be 1
        Should -Invoke Get-Process -ParameterFilter { $Name -contains 'Codex' -and $Name -contains 'ChatGPT' }
    }
}
