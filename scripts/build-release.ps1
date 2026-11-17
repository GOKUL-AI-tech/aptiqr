param(
    [ValidateSet('android', 'windows', 'web', 'all')]
    [string]$Target = 'all',
    [string]$Config = 'env/dev.json'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$previousTemp = $env:TEMP
$previousTmp = $env:TMP

function Invoke-Checked {
    param([string]$Command, [string[]]$Arguments)
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Command failed with exit code $LASTEXITCODE."
    }
}

Push-Location $projectRoot
try {
    if (-not (Test-Path -LiteralPath $Config -PathType Leaf)) {
        throw "Missing configuration file: $Config. Copy env/dev.json.example and fill in your Supabase settings."
    }
    # Long temporary paths can prevent Java's Windows loopback sockets from opening.
    $buildTemp = Join-Path $projectRoot 'build/java-tmp'
    New-Item -ItemType Directory -Force -Path $buildTemp | Out-Null
    $env:TEMP = $buildTemp
    $env:TMP = $buildTemp

    Invoke-Checked flutter @('pub', 'get')
    Invoke-Checked dart @('run', 'build_runner', 'build')
    Invoke-Checked flutter @('analyze', '--no-fatal-infos')
    Invoke-Checked flutter @('test')
    if ($Target -in @('android', 'all')) {
        Invoke-Checked flutter @('build', 'apk', '--release', "--dart-define-from-file=$Config")
        Write-Host 'APK: build/app/outputs/flutter-apk/app-release.apk'
    }
    if ($Target -in @('windows', 'all')) {
        Invoke-Checked flutter @('build', 'windows', '--release', "--dart-define-from-file=$Config")
        Compress-Archive -Path 'build/windows/x64/runner/Release/*' -DestinationPath 'build/AptiQR-windows-x64.zip' -Force
        Write-Host 'Windows package: build/AptiQR-windows-x64.zip. Extract the whole ZIP before running aptiqr.exe.'
    }
    if ($Target -in @('web', 'all')) {
        Invoke-Checked flutter @('build', 'web', '--release', '--no-tree-shake-icons', "--dart-define-from-file=$Config")
        Write-Host 'Web build: build/web/'
    }
} finally {
    $env:TEMP = $previousTemp
    $env:TMP = $previousTmp
    Pop-Location
}
