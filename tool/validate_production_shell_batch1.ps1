param(
  [switch]$Install,
  [string]$DeviceId = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Resolve-Adb {
  $command = Get-Command adb -ErrorAction SilentlyContinue
  if ($command) { return $command.Source }

  $candidates = @()
  if ($env:ANDROID_SDK_ROOT) {
    $candidates += (Join-Path $env:ANDROID_SDK_ROOT "platform-tools\adb.exe")
  }
  if ($env:ANDROID_HOME) {
    $candidates += (Join-Path $env:ANDROID_HOME "platform-tools\adb.exe")
  }
  $localProperties = Join-Path $root "android\local.properties"
  if (Test-Path $localProperties) {
    $sdkLine = Get-Content $localProperties |
      Where-Object { $_ -match '^sdk\.dir=' } |
      Select-Object -First 1
    if ($sdkLine) {
      $sdk = ($sdkLine -replace '^sdk\.dir=', '') -replace '\\\\', '\'
      $candidates += (Join-Path $sdk "platform-tools\adb.exe")
    }
  }

  foreach ($candidate in $candidates) {
    if (Test-Path $candidate) { return $candidate }
  }
  return $null
}

$changedDartFiles = @(
  "lib/core/navigation/app_destination.dart",
  "lib/core/navigation/app_navigator.dart",
  "lib/core/theme/fluviai_commercial_tokens.dart",
  "lib/core/utility/fluviai_utility_registry.dart",
  "lib/features/commercial_home/presentation/commercial_home_page.dart",
  "lib/features/figma_complete/presentation/figma_destination_router.dart",
  "lib/features/shell/presentation/activity_hub_page.dart",
  "lib/features/shell/presentation/utilities_hub_page.dart",
  "lib/screens/main_navigation.dart",
  "lib/widgets/navigation/fluviai_connectivity_pill.dart",
  "lib/widgets/navigation/fluviai_navigation.dart",
  "test/shell_runtime_navigation_test.dart",
  "test/utility_registry_test.dart"
)

Write-Host "[1/7] Flutter environment" -ForegroundColor Cyan
flutter --version
flutter doctor -v

Write-Host "[2/7] Dependencies" -ForegroundColor Cyan
flutter pub get

Write-Host "[3/7] Format" -ForegroundColor Cyan
dart format $changedDartFiles

Write-Host "[4/7] Analyze" -ForegroundColor Cyan
flutter analyze

Write-Host "[5/7] Targeted tests" -ForegroundColor Cyan
flutter test `
  test/utility_registry_test.dart `
  test/home_navigation_shell_test.dart `
  test/shell_runtime_navigation_test.dart `
  test/runtime_integrity_test.dart `
  test/fluviai_responsive_components_test.dart

Write-Host "[6/7] Android debug build" -ForegroundColor Cyan
if (-not $env:MAPBOX_ACCESS_TOKEN) {
  throw "MAPBOX_ACCESS_TOKEN is required and must begin with pk."
}
flutter build apk --debug

if ($Install) {
  Write-Host "[7/7] Install on Android device" -ForegroundColor Cyan
  $adb = Resolve-Adb
  if (-not $adb) {
    throw "adb.exe was not found. Add Android platform-tools to PATH or configure android/local.properties."
  }

  $adbArgs = @()
  if ($DeviceId) { $adbArgs += @("-s", $DeviceId) }

  & $adb @adbArgs devices
  & $adb @adbArgs install -r "build\app\outputs\flutter-apk\app-debug.apk"
  & $adb @adbArgs shell am force-stop com.example.fishtrack
  & $adb @adbArgs shell monkey -p com.example.fishtrack -c android.intent.category.LAUNCHER 1
  Write-Host "Installed and launched com.example.fishtrack" -ForegroundColor Green
} else {
  Write-Host "[7/7] Install skipped. Re-run with -Install for Samsung QA." -ForegroundColor Yellow
}

Write-Host "Batch 1 validation completed." -ForegroundColor Green
