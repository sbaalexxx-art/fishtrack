param(
    [string]$DeviceId = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding

$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

function Invoke-NativeStep {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][scriptblock]$Command,
        [Parameter(Mandatory = $true)][string]$LogPath
    )

    Write-Host $Label -ForegroundColor Cyan

    $previousPreference = $ErrorActionPreference
    $exitCode = 1

    try {
        # Windows PowerShell 5.1 can wrap native stderr as NativeCommandError.
        # The real result is the native process exit code.
        $ErrorActionPreference = "Continue"
        & $Command 2>&1 |
            ForEach-Object {
                $_
                "$_" | Out-File -FilePath $LogPath -Append -Encoding utf8
            }
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    if ($exitCode -ne 0) {
        throw "$Label failed with exit code $exitCode. Log: $LogPath"
    }
}

if (-not (Test-Path (Join-Path $projectRoot "pubspec.yaml"))) {
    throw "pubspec.yaml was not found in $projectRoot"
}

if ([string]::IsNullOrWhiteSpace($env:MAPBOX_ACCESS_TOKEN)) {
    $userToken = [Environment]::GetEnvironmentVariable("MAPBOX_ACCESS_TOKEN", "User")
    if (-not [string]::IsNullOrWhiteSpace($userToken)) {
        $env:MAPBOX_ACCESS_TOKEN = $userToken
    }
}

if ([string]::IsNullOrWhiteSpace($env:MAPBOX_ACCESS_TOKEN) -or
    -not $env:MAPBOX_ACCESS_TOKEN.StartsWith("pk.")) {
    throw "MAPBOX_ACCESS_TOKEN is missing or is not a public pk token."
}

if ($null -eq (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw "Flutter was not found in PATH."
}

$adbCommand = Get-Command adb -ErrorAction SilentlyContinue
if ($null -ne $adbCommand) {
    $adb = $adbCommand.Source
}
else {
    $adb = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"
    if (-not (Test-Path $adb)) {
        throw "ADB was not found."
    }
}

$stamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
$outputDir = Join-Path $projectRoot "outputs\rc2_2_$stamp"
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

Invoke-NativeStep `
    -Label "[1/7] flutter pub get" `
    -LogPath (Join-Path $outputDir "01_pub_get.txt") `
    -Command { flutter pub get }

Invoke-NativeStep `
    -Label "[2/7] flutter analyze" `
    -LogPath (Join-Path $outputDir "02_analyze.txt") `
    -Command { flutter analyze --no-pub }

Invoke-NativeStep `
    -Label "[3/7] Flutter tests" `
    -LogPath (Join-Path $outputDir "03_tests.txt") `
    -Command {
        flutter test --no-pub `
            test/app_theme_contract_test.dart `
            test/home_navigation_shell_test.dart `
            test/shell_runtime_navigation_test.dart `
            test/commercial_home_page_test.dart
    }

Invoke-NativeStep `
    -Label "[4/7] Build debug APK" `
    -LogPath (Join-Path $outputDir "04_build.txt") `
    -Command {
        flutter build apk --debug --no-pub `
            --dart-define="MAPBOX_ACCESS_TOKEN=$env:MAPBOX_ACCESS_TOKEN"
    }

$apk = Join-Path $projectRoot "build\app\outputs\flutter-apk\app-debug.apk"
if (-not (Test-Path $apk)) {
    throw "APK was not created: $apk"
}

Write-Host "[5/7] Check Android device" -ForegroundColor Cyan
$deviceOutput = @(& $adb devices -l)
$deviceOutput | Out-File -FilePath (Join-Path $outputDir "05_devices.txt") -Encoding utf8
$deviceOutput | ForEach-Object { Write-Host $_ }
if ($LASTEXITCODE -ne 0) {
    throw "adb devices failed."
}

$deviceLines = @($deviceOutput | Select-String '^\S+\s+device\b')
if ($deviceLines.Count -lt 1) {
    throw "No authorized Android device was detected."
}

if ([string]::IsNullOrWhiteSpace($DeviceId)) {
    $DeviceId = (($deviceLines[0].Line -split '\s+')[0]).Trim()
}

$selectedDevice = @($deviceLines | Where-Object { $_.Line -match "^$([regex]::Escape($DeviceId))\s+device\b" })
if ($selectedDevice.Count -lt 1) {
    throw "Device $DeviceId is not connected and authorized."
}

Write-Host "Device: $DeviceId" -ForegroundColor Green

Invoke-NativeStep `
    -Label "[6/7] Install APK" `
    -LogPath (Join-Path $outputDir "06_install.txt") `
    -Command { & $adb -s $DeviceId install -r $apk }

& $adb -s $DeviceId shell monkey `
    -p com.example.fishtrack `
    -c android.intent.category.LAUNCHER 1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "FluviAI could not be launched."
}

Start-Sleep -Seconds 8

Write-Host "[7/7] Capture Samsung screenshot" -ForegroundColor Cyan
$remoteScreenshot = "/sdcard/fluviai_rc2_2_$stamp.png"
$localScreenshot = Join-Path $outputDir "home_samsung.png"

& $adb -s $DeviceId shell screencap -p $remoteScreenshot
if ($LASTEXITCODE -ne 0) {
    throw "Device screenshot failed."
}

& $adb -s $DeviceId pull $remoteScreenshot $localScreenshot | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Screenshot transfer failed."
}

& $adb -s $DeviceId shell rm $remoteScreenshot | Out-Null

Copy-Item -LiteralPath $apk `
    -Destination (Join-Path $outputDir "FluviAI-RC2.2-debug.apk") `
    -Force

Write-Host ""
Write-Host "FLUVIAI RC2.2 QA COMPLETED" -ForegroundColor Green
Write-Host "Results: $outputDir" -ForegroundColor Green
Get-ChildItem $outputDir | Select-Object Name, Length, LastWriteTime
