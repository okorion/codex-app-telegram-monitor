param(
    [string]$Version = "",
    [string]$ArchivePath = "",
    [string]$ChecksumPath = "",
    [string]$Ref = "HEAD"
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = (Get-Content -LiteralPath (Join-Path $PSScriptRoot "VERSION") -Raw -Encoding UTF8).Trim()
}

if ([string]::IsNullOrWhiteSpace($ArchivePath)) {
    $ArchivePath = Join-Path $env:TEMP "codex-app-telegram-monitor-$Version.zip"
}

if ([string]::IsNullOrWhiteSpace($ChecksumPath)) {
    $ChecksumPath = "$ArchivePath.sha256"
}

$archiveParent = Split-Path -Parent $ArchivePath
if (![string]::IsNullOrWhiteSpace($archiveParent) -and !(Test-Path -LiteralPath $archiveParent)) {
    New-Item -ItemType Directory -Path $archiveParent -Force | Out-Null
}

Remove-Item -LiteralPath $ArchivePath, $ChecksumPath -Force -ErrorAction SilentlyContinue

git archive --format zip --output $ArchivePath $Ref
if ($LASTEXITCODE -ne 0) {
    throw "git archive failed for ref $Ref."
}

if (!(Test-Path -LiteralPath $ArchivePath)) {
    throw "Release archive was not created."
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $ArchivePath))
try {
    $names = @($zip.Entries | ForEach-Object { $_.FullName })
    $versionEntry = $zip.Entries | Where-Object { $_.FullName -eq "VERSION" } | Select-Object -First 1
    $archiveVersion = ""
    if ($versionEntry) {
        $stream = $versionEntry.Open()
        $reader = New-Object System.IO.StreamReader -ArgumentList $stream, [System.Text.Encoding]::UTF8
        try {
            $archiveVersion = $reader.ReadToEnd().Trim()
        } finally {
            $reader.Dispose()
            $stream.Dispose()
        }
    }
} finally {
    $zip.Dispose()
}

foreach ($required in @("README.md", "install_all.ps1", "configure-codex-telegram.ps1", ".env.example", "VERSION")) {
    if ($names -notcontains $required) {
        throw "Release archive is missing required file: $required"
    }
}

if ($archiveVersion -ne $Version) {
    throw "Release archive VERSION ($archiveVersion) does not match expected version ($Version)."
}

$forbidden = @($names | Where-Object {
    $_ -eq ".env" -or
    $_ -eq "testResults.xml" -or
    $_ -like "logs/*" -or
    $_ -like "state/*"
})
if ($forbidden.Count -gt 0) {
    throw "Release archive contains local-only files:`n$($forbidden -join "`n")"
}

$hash = Get-FileHash -Algorithm SHA256 -LiteralPath $ArchivePath
"$($hash.Hash.ToLowerInvariant())  $(Split-Path -Leaf $ArchivePath)" |
    Set-Content -LiteralPath $ChecksumPath -Encoding ASCII

[PSCustomObject]@{
    Version = $Version
    ArchivePath = $ArchivePath
    ChecksumPath = $ChecksumPath
    ArchiveBytes = (Get-Item -LiteralPath $ArchivePath).Length
    ArchiveVersion = $archiveVersion
    EntryCount = $names.Count
    RequiredFilesOk = $true
    ForbiddenFiles = $forbidden.Count
    Sha256 = $hash.Hash.ToLowerInvariant()
} | Format-List
