param(
  [switch]$Install,
  [string]$DeviceId = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Invoke-CheckedNative {
  param(
    [Parameter(Mandatory = $true)][string]$Executable,
    [string[]]$ArgumentList = @(),
    [string]$FailureMessage = ""
  )

  & $Executable @ArgumentList
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0) {
    $message = if ($FailureMessage) {
      $FailureMessage
    } else {
      "$Executable failed with exit code $exitCode."
    }
    throw $message
  }
}

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

function Resolve-ApplicationId {
  $gradle = Join-Path $root "android\app\build.gradle.kts"
  if (Test-Path $gradle) {
    $applicationIdMatch = Select-String -Path $gradle -Pattern 'applicationId\s*=\s*"([^"]+)"' |
      Select-Object -First 1
    if ($applicationIdMatch -and $applicationIdMatch.Matches.Count -gt 0) {
      return $applicationIdMatch.Matches[0].Groups[1].Value
    }
  }
  return "com.example.fishtrack"
}

$changedDartFiles = @(
  "lib/core/context/home_runtime_context.dart",
  "lib/core/utility/fluviai_utility_registry.dart",
  "lib/features/commercial_home/presentation/commercial_home_page.dart",
  "lib/features/figma_complete/presentation/figma_community_pages.dart",
  "lib/features/figma_complete/presentation/figma_foundation.dart",
  "lib/features/shell/presentation/utilities_hub_page.dart",
  "lib/screens/main_navigation.dart",
  "test/home_runtime_context_test.dart",
  "test/commercial_home_page_test.dart",
  "test/utility_registry_test.dart",
  "test/utilities_hub_context_test.dart",
  "test/new_session_runtime_guard_test.dart"
)

Write-Host "[1/8] Flutter environment" -ForegroundColor Cyan
Invoke-CheckedNative -Executable "flutter" -ArgumentList @("--version")
& flutter doctor -v
if ($LASTEXITCODE -ne 0) {
  Write-Warning "flutter doctor reported environment issues. Validation continues because build/test gates below are authoritative."
}

Write-Host "[2/8] Dependencies" -ForegroundColor Cyan
Invoke-CheckedNative -Executable "flutter" -ArgumentList @("pub", "get") -FailureMessage "flutter pub get failed."

Write-Host "[3/8] Format Batch 2 files" -ForegroundColor Cyan
Invoke-CheckedNative -Executable "dart" -ArgumentList (@("format") + $changedDartFiles) -FailureMessage "dart format failed."

Write-Host "[4/8] Analyze complete project" -ForegroundColor Cyan
Invoke-CheckedNative -Executable "flutter" -ArgumentList @("analyze") -FailureMessage "flutter analyze failed. Batch 2 was not built or installed."

Write-Host "[5/8] Context and registry tests" -ForegroundColor Cyan
Invoke-CheckedNative -Executable "flutter" -ArgumentList @(
  "test",
  "test/home_runtime_context_test.dart",
  "test/utility_registry_test.dart",
  "test/commercial_home_page_test.dart",
  "test/utilities_hub_context_test.dart",
  "test/new_session_runtime_guard_test.dart"
) -FailureMessage "Batch 2 context/registry tests failed. Batch 2 was not built or installed."

Write-Host "[6/8] Shell and responsive regression tests" -ForegroundColor Cyan
Invoke-CheckedNative -Executable "flutter" -ArgumentList @(
  "test",
  "test/home_navigation_shell_test.dart",
  "test/shell_runtime_navigation_test.dart",
  "test/runtime_integrity_test.dart",
  "test/fluviai_responsive_components_test.dart",
  "test/figma_complete_contract_test.dart"
) -FailureMessage "Shell/responsive regression tests failed. Batch 2 was not built or installed."

Write-Host "[7/8] Android debug build" -ForegroundColor Cyan
if (-not $env:MAPBOX_ACCESS_TOKEN -or -not $env:MAPBOX_ACCESS_TOKEN.StartsWith("pk.")) {
  throw "MAPBOX_ACCESS_TOKEN is required and must begin with pk."
}

$apk = Join-Path $root "build\app\outputs\flutter-apk\app-debug.apk"
if (Test-Path $apk) {
  Remove-Item -LiteralPath $apk -Force
}
$buildStartedUtc = [DateTime]::UtcNow
Invoke-CheckedNative -Executable "flutter" -ArgumentList @("build", "apk", "--debug") -FailureMessage "Android debug build failed. No APK was installed."

if (-not (Test-Path $apk)) {
  throw "Build reported success, but the debug APK was not found at $apk."
}
$apkInfo = Get-Item -LiteralPath $apk
if ($apkInfo.LastWriteTimeUtc -lt $buildStartedUtc.AddSeconds(-2)) {
  throw "The APK at $apk is stale and was not produced by this validation run."
}

if ($Install) {
  Write-Host "[8/8] Install, standalone launch and capture" -ForegroundColor Cyan
  $adb = Resolve-Adb
  if (-not $adb) {
    throw "adb.exe was not found. Add Android platform-tools to PATH or configure android/local.properties."
  }

  $adbArgs = @()
  if ($DeviceId) { $adbArgs += @("-s", $DeviceId) }

  $applicationId = Resolve-ApplicationId

  Invoke-CheckedNative -Executable $adb -ArgumentList ($adbArgs + @("devices"))
  Invoke-CheckedNative -Executable $adb -ArgumentList ($adbArgs + @("install", "-r", $apk)) -FailureMessage "ADB install failed."
  Invoke-CheckedNative -Executable $adb -ArgumentList ($adbArgs + @("shell", "am", "force-stop", $applicationId))
  Invoke-CheckedNative -Executable $adb -ArgumentList ($adbArgs + @("logcat", "-c"))
  Invoke-CheckedNative -Executable $adb -ArgumentList ($adbArgs + @("shell", "monkey", "-p", $applicationId, "-c", "android.intent.category.LAUNCHER", "1")) -FailureMessage "Standalone launch command failed."
  Start-Sleep -Seconds 4

  $appPid = (& $adb @adbArgs shell pidof $applicationId).Trim()
  $pidExitCode = $LASTEXITCODE
  if ($pidExitCode -ne 0 -or -not $appPid) {
    throw "$applicationId did not remain alive after standalone launch."
  }

  $qaDirectory = Join-Path $root "build\qa\batch2"
  New-Item -ItemType Directory -Path $qaDirectory -Force | Out-Null
  $remoteScreenshot = "/sdcard/fluviai_batch2_home.png"
  $localScreenshot = Join-Path $qaDirectory "home_after_standalone_launch.png"
  Invoke-CheckedNative -Executable $adb -ArgumentList ($adbArgs + @("shell", "screencap", "-p", $remoteScreenshot))
  Invoke-CheckedNative -Executable $adb -ArgumentList ($adbArgs + @("pull", $remoteScreenshot, $localScreenshot))
  Invoke-CheckedNative -Executable $adb -ArgumentList ($adbArgs + @("shell", "rm", $remoteScreenshot))

  $logPath = Join-Path $qaDirectory "logcat_after_standalone_launch.txt"
  & $adb @adbArgs logcat -d -t 600 | Out-File -FilePath $logPath -Encoding utf8
  if ($LASTEXITCODE -ne 0) {
    throw "Could not capture logcat after standalone launch."
  }

  Write-Host "Installed and launched $applicationId (pid $appPid)" -ForegroundColor Green
  Write-Host "QA screenshot: $localScreenshot" -ForegroundColor Green
  Write-Host "QA logcat: $logPath" -ForegroundColor Green
} else {
  Write-Host "[8/8] Install skipped. Re-run with -Install for Samsung QA." -ForegroundColor Yellow
}

Write-Host "Batch 2 validation completed." -ForegroundColor Green
