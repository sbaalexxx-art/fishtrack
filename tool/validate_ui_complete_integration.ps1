param(
  [switch]$Install,
  [string]$DeviceId = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

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

function Invoke-FlutterTestAttempt {
  param(
    [Parameter(Mandatory = $true)][string[]]$ArgumentList,
    [Parameter(Mandatory = $true)][string]$LogPath
  )

  if (Test-Path -LiteralPath $LogPath) {
    Remove-Item -LiteralPath $LogPath -Force
  }

  $script:FlutterTestExitCode = -1

  & flutter @ArgumentList 2>&1 |
    ForEach-Object {
      $_ | Tee-Object -FilePath $LogPath -Append
    }

  $script:FlutterTestExitCode = $LASTEXITCODE
}

function Invoke-ReliableFullFlutterSuite {
  param(
    [Parameter(Mandatory = $true)][string]$QaDirectory
  )

  $suiteDirectory = Join-Path $QaDirectory "full_suite"
  New-Item -ItemType Directory -Path $suiteDirectory -Force | Out-Null

  $originalTemp = $env:TEMP
  $originalTmp = $env:TMP

  try {
    for ($attempt = 1; $attempt -le 2; $attempt++) {
      $attemptTemp = Join-Path $suiteDirectory "temp_attempt_$attempt"
      $attemptLog = Join-Path $suiteDirectory "attempt_$attempt.txt"

      if (Test-Path -LiteralPath $attemptTemp) {
        Remove-Item -LiteralPath $attemptTemp -Recurse -Force
      }
      New-Item -ItemType Directory -Path $attemptTemp -Force | Out-Null

      $env:TEMP = $attemptTemp
      $env:TMP = $attemptTemp

      Write-Host "Full-suite attempt $attempt/2" -ForegroundColor DarkCyan

      Invoke-FlutterTestAttempt `
        -ArgumentList @(
          "test",
          "--reporter",
          "expanded",
          "--concurrency=1"
        ) `
        -LogPath $attemptLog

      $exitCode = $script:FlutterTestExitCode
      if ($exitCode -eq 0) {
        Copy-Item `
          -LiteralPath $attemptLog `
          -Destination (Join-Path $QaDirectory "full_suite_console.txt") `
          -Force
        Write-Host "Full Flutter test suite PASS." -ForegroundColor Green
        return
      }

      $attemptOutput = if (Test-Path -LiteralPath $attemptLog) {
        Get-Content -LiteralPath $attemptLog -Raw
      } else {
        ""
      }

      $isListenerCleanupFailure =
        $attemptOutput -match 'unhandled error during finalization of test' -and
        $attemptOutput -match 'flutter_test_listener' -and
        $attemptOutput -match 'PathNotFoundException:\s+Deletion failed'

      if ($isListenerCleanupFailure -and $attempt -lt 2) {
        Write-Warning (
          "Flutter test listener cleanup failed after test execution. " +
          "Retrying once with a fresh isolated TEMP directory."
        )
        continue
      }

      Copy-Item `
        -LiteralPath $attemptLog `
        -Destination (Join-Path $QaDirectory "full_suite_console.txt") `
        -Force

      if ($isListenerCleanupFailure) {
        throw (
          "The full suite was interrupted twice by Flutter test-listener " +
          "cleanup on Windows. No APK was built or installed. " +
          "See build\qa\ui_complete\full_suite\attempt_$attempt.txt."
        )
      }

      throw (
        "The full Flutter test suite contains an actual test failure. " +
        "No APK was built or installed. " +
        "See build\qa\ui_complete\full_suite\attempt_$attempt.txt."
      )
    }
  }
  finally {
    $env:TEMP = $originalTemp
    $env:TMP = $originalTmp
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

  $localProperties = Join-Path $projectRoot "android\local.properties"
  if (Test-Path -LiteralPath $localProperties) {
    $sdkLine = Get-Content -LiteralPath $localProperties |
      Where-Object { $_ -match '^sdk\.dir=' } |
      Select-Object -First 1
    if ($sdkLine) {
      $sdk = ($sdkLine -replace '^sdk\.dir=', '') -replace '\\\\', '\'
      $candidates += (Join-Path $sdk "platform-tools\adb.exe")
    }
  }

  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate) { return $candidate }
  }
  return $null
}

function Resolve-ApplicationId {
  $gradle = Join-Path $projectRoot "android\app\build.gradle.kts"
  if (Test-Path -LiteralPath $gradle) {
    $applicationIdMatch = Select-String `
      -Path $gradle `
      -Pattern 'applicationId\s*=\s*"([^"]+)"' |
      Select-Object -First 1
    if ($applicationIdMatch -and $applicationIdMatch.Matches.Count -gt 0) {
      return $applicationIdMatch.Matches[0].Groups[1].Value
    }
  }
  return "com.example.fishtrack"
}

function Assert-ProtectedContracts {
  $canonicalHomeSource = Get-Content `
    -LiteralPath (Join-Path $projectRoot "lib\features\commercial_home\presentation\commercial_home_page.dart") `
    -Raw
  if ($canonicalHomeSource -match '\bHomePremiumMap\b' -or
      $canonicalHomeSource -match 'commercial-home-map-hero') {
    throw "The legacy embedded Home map was reintroduced."
  }

  $navigationOwners = @(
    Get-ChildItem (Join-Path $projectRoot "lib") `
      -Recurse `
      -Filter "*.dart" `
      -File |
      Where-Object {
        $_.FullName -notmatch '[\\/]design_lab[\\/]' -and
        $_.Name -ne 'main_design_lab.dart' -and
        (Get-Content -LiteralPath $_.FullName -Raw) -match 'bottomNavigationBar\s*:'
      }
  )
  if (@($navigationOwners).Count -ne 1 -or
      $navigationOwners[0].FullName -notmatch '[\\/]screens[\\/]main_navigation\.dart$') {
    throw "Bottom navigation must be owned only by main_navigation.dart."
  }

  $registrySource = Get-Content `
    -LiteralPath (Join-Path $projectRoot "lib\core\utility\fluviai_utility_registry.dart") `
    -Raw
  $utilityIds = [regex]::Matches($registrySource, "id:\s*'([^']+)'")
  if ($utilityIds.Count -ne 34) {
    throw "Expected 34 protected utilities, found $($utilityIds.Count)."
  }

  $navigatorSource = Get-Content `
    -LiteralPath (Join-Path $projectRoot "lib\core\navigation\app_navigator.dart") `
    -Raw
  if ($navigatorSource -notmatch 'CommercialHomeDataSource\? dataSource' -or
      $navigatorSource -notmatch 'dataSource:\s*dataSource') {
    throw "Runtime data-source propagation is missing from AppNavigator."
  }

  $environmentSource = Get-Content `
    -LiteralPath (Join-Path $projectRoot "lib\features\figma_complete\presentation\figma_environment_pages.dart") `
    -Raw
  foreach ($requiredToken in @(
    "batch3-water-open-weather",
    "batch3-water-open-fluvi",
    "batch3-weather-open-water",
    "batch3-weather-open-fluvi",
    "batch3-fluvi-open-water",
    "batch3-fluvi-open-weather",
    "figma-weather-scroll"
  )) {
    if ($environmentSource -notmatch [regex]::Escape($requiredToken)) {
      throw "Missing protected integration token: $requiredToken"
    }
  }
}

$qaDirectory = Join-Path $projectRoot "build\qa\ui_complete"
New-Item -ItemType Directory -Path $qaDirectory -Force | Out-Null
$validationLog = Join-Path $qaDirectory "validation_console.txt"
Start-Transcript -Path $validationLog -Force | Out-Null

try {
  Write-Host "[1/10] Protected product contracts" -ForegroundColor Cyan
  Assert-ProtectedContracts
  Write-Host "Protected contracts PASS." -ForegroundColor Green

  Write-Host "[2/10] Flutter environment" -ForegroundColor Cyan
  Invoke-CheckedNative -Executable "flutter" -ArgumentList @("--version")
  & flutter doctor -v
  if ($LASTEXITCODE -ne 0) {
    Write-Warning "flutter doctor reported non-Android environment issues. Test/build/install gates remain authoritative."
  }

  Write-Host "[3/10] Dependencies" -ForegroundColor Cyan
  Invoke-CheckedNative `
    -Executable "flutter" `
    -ArgumentList @("pub", "get") `
    -FailureMessage "flutter pub get failed."

  Write-Host "[4/10] Format complete source and tests" -ForegroundColor Cyan
  Invoke-CheckedNative `
    -Executable "dart" `
    -ArgumentList @("format", "lib", "test") `
    -FailureMessage "dart format failed."

  Write-Host "[5/10] Analyze complete project" -ForegroundColor Cyan
  Invoke-CheckedNative `
    -Executable "flutter" `
    -ArgumentList @("analyze") `
    -FailureMessage "flutter analyze failed. No APK was built or installed."

  Write-Host "[6/10] UI-complete contract and runtime-state tests" -ForegroundColor Cyan
  Invoke-CheckedNative `
    -Executable "flutter" `
    -ArgumentList @(
      "test",
      "test/ui_complete_integration_test.dart",
      "test/ui_complete_runtime_state_test.dart",
      "test/batch3_priority_utilities_integration_test.dart",
      "test/utility_registry_test.dart",
      "test/figma_complete_contract_test.dart",
      "test/figma_runtime_manifest_test.dart",
      "test/home_navigation_shell_test.dart",
      "test/shell_runtime_navigation_test.dart",
      "test/commercial_home_page_test.dart",
      "test/fluviai_responsive_components_test.dart"
    ) `
    -FailureMessage "UI-complete contract tests failed. No APK was built or installed."

  Write-Host "[7/10] Full project test suite (serial and isolated)" -ForegroundColor Cyan
  Invoke-ReliableFullFlutterSuite -QaDirectory $qaDirectory

  Write-Host "[8/10] Android debug build" -ForegroundColor Cyan
  if (-not $env:MAPBOX_ACCESS_TOKEN -or
      -not $env:MAPBOX_ACCESS_TOKEN.StartsWith("pk.")) {
    throw "MAPBOX_ACCESS_TOKEN is required and must begin with pk."
  }

  $apk = Join-Path $projectRoot "build\app\outputs\flutter-apk\app-debug.apk"
  if (Test-Path -LiteralPath $apk) {
    Remove-Item -LiteralPath $apk -Force
  }
  $buildStartedUtc = [DateTime]::UtcNow
  Invoke-CheckedNative `
    -Executable "flutter" `
    -ArgumentList @("build", "apk", "--debug") `
    -FailureMessage "Android debug build failed. No APK was installed."

  if (-not (Test-Path -LiteralPath $apk)) {
    throw "Build reported success, but the APK was not found: $apk"
  }
  $apkInfo = Get-Item -LiteralPath $apk
  if ($apkInfo.LastWriteTimeUtc -lt $buildStartedUtc.AddSeconds(-2)) {
    throw "The APK is stale and was not produced by this validation run."
  }
  $apkHash = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash
  $apkHash | Set-Content `
    -LiteralPath (Join-Path $qaDirectory "app-debug.sha256.txt") `
    -Encoding UTF8

  if ($Install) {
    Write-Host "[9/10] Install and standalone Samsung launch" -ForegroundColor Cyan
    $adb = Resolve-Adb
    if (-not $adb) {
      throw "adb.exe was not found. Configure Android platform-tools."
    }

    $adbArgs = @()
    if ($DeviceId) { $adbArgs += @("-s", $DeviceId) }
    $applicationId = Resolve-ApplicationId

    Invoke-CheckedNative -Executable $adb -ArgumentList ($adbArgs + @("devices"))
    Invoke-CheckedNative `
      -Executable $adb `
      -ArgumentList ($adbArgs + @("install", "-r", $apk)) `
      -FailureMessage "ADB install failed."
    Invoke-CheckedNative `
      -Executable $adb `
      -ArgumentList ($adbArgs + @("shell", "am", "force-stop", $applicationId))
    Invoke-CheckedNative `
      -Executable $adb `
      -ArgumentList ($adbArgs + @("logcat", "-c"))
    Invoke-CheckedNative `
      -Executable $adb `
      -ArgumentList ($adbArgs + @(
        "shell",
        "monkey",
        "-p",
        $applicationId,
        "-c",
        "android.intent.category.LAUNCHER",
        "1"
      )) `
      -FailureMessage "Standalone launch failed."
    Start-Sleep -Seconds 5

    $appPid = (& $adb @adbArgs shell pidof $applicationId).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $appPid) {
      throw "$applicationId did not remain alive after standalone launch."
    }

    Write-Host "[10/10] Capture QA evidence" -ForegroundColor Cyan
    $remoteScreenshot = "/sdcard/fluviai_ui_complete_home.png"
    $localScreenshot = Join-Path $qaDirectory "home_after_standalone_launch.png"
    Invoke-CheckedNative `
      -Executable $adb `
      -ArgumentList ($adbArgs + @("shell", "screencap", "-p", $remoteScreenshot))
    Invoke-CheckedNative `
      -Executable $adb `
      -ArgumentList ($adbArgs + @("pull", $remoteScreenshot, $localScreenshot))
    Invoke-CheckedNative `
      -Executable $adb `
      -ArgumentList ($adbArgs + @("shell", "rm", $remoteScreenshot))

    $logPath = Join-Path $qaDirectory "logcat_after_standalone_launch.txt"
    & $adb @adbArgs logcat -d -t 1200 |
      Out-File -FilePath $logPath -Encoding utf8
    if ($LASTEXITCODE -ne 0) {
      throw "Could not capture logcat after standalone launch."
    }

    $summary = @(
      "FluviAI UI Complete Integration",
      "Validated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')",
      "Application: $applicationId",
      "PID: $appPid",
      "APK: $apk",
      "APK SHA-256: $apkHash",
      "Screenshot: $localScreenshot",
      "Logcat: $logPath",
      "Technical status: PASS",
      "Visual status: pending final multi-screen QA"
    )
    $summary | Set-Content `
      -LiteralPath (Join-Path $qaDirectory "validation_summary.txt") `
      -Encoding UTF8

    Write-Host "Installed and launched $applicationId (pid $appPid)" -ForegroundColor Green
    Write-Host "QA screenshot: $localScreenshot" -ForegroundColor Green
    Write-Host "QA logcat: $logPath" -ForegroundColor Green
  } else {
    Write-Host "[9/10] Install skipped. Re-run with -Install for Samsung QA." -ForegroundColor Yellow
    Write-Host "[10/10] QA capture skipped because installation was not requested." -ForegroundColor Yellow
  }

  Write-Host "FluviAI UI Complete Integration validation completed." -ForegroundColor Green
}
finally {
  Stop-Transcript | Out-Null
}
