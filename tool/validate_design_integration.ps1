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
    if (Test-Path -LiteralPath $candidate) {
      return $candidate
    }
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

    if ($applicationIdMatch -and
        @($applicationIdMatch.Matches).Count -gt 0) {
      return $applicationIdMatch.Matches[0].Groups[1].Value
    }
  }

  return "com.example.fishtrack"
}

function Assert-DesignContracts {
  $canonicalHomePath = Join-Path $projectRoot `
    "lib\features\commercial_home\presentation\commercial_home_page.dart"

  if (-not (Test-Path -LiteralPath $canonicalHomePath)) {
    throw "Canonical Home source is missing."
  }

  $canonicalHomeSource = Get-Content `
    -LiteralPath $canonicalHomePath `
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
        (Get-Content -LiteralPath $_.FullName -Raw) -match
          'bottomNavigationBar\s*:'
      }
  )

  if (@($navigationOwners).Count -ne 1 -or
      $navigationOwners[0].FullName -notmatch
        '[\\/]screens[\\/]main_navigation\.dart$') {
    throw "Bottom navigation must be owned only by main_navigation.dart."
  }

  $registryPath = Join-Path $projectRoot `
    "lib\core\utility\fluviai_utility_registry.dart"

  if (-not (Test-Path -LiteralPath $registryPath)) {
    throw "Protected utility registry is missing."
  }

  $registrySource = Get-Content `
    -LiteralPath $registryPath `
    -Raw

  $utilityIds = [regex]::Matches(
    $registrySource,
    "id:\s*'([^']+)'"
  )

  if ($utilityIds.Count -ne 34) {
    throw "Expected 34 protected utilities, found $($utilityIds.Count)."
  }

  $shellPath = Join-Path $projectRoot "lib\screens\main_navigation.dart"

  if (-not (Test-Path -LiteralPath $shellPath)) {
    throw "Canonical application shell is missing."
  }

  Write-Host "Design contracts PASS." -ForegroundColor Green
}

$qaDirectory = Join-Path $projectRoot "build\qa\design_integration"
New-Item -ItemType Directory -Path $qaDirectory -Force | Out-Null

$validationLog = Join-Path $qaDirectory "validation_console.txt"

try {
  Write-Host "[1/8] Protected design contracts" -ForegroundColor Cyan
  Assert-DesignContracts

  Write-Host "[2/8] Dependencies" -ForegroundColor Cyan
  Invoke-CheckedNative `
    -Executable "flutter" `
    -ArgumentList @("pub", "get") `
    -FailureMessage "flutter pub get failed."

  Write-Host "[3/8] Format design source and UI tests" -ForegroundColor Cyan
  Invoke-CheckedNative `
    -Executable "dart" `
    -ArgumentList @(
      "format",
      "lib",
      "test/commercial_home_page_test.dart",
      "test/fluviai_responsive_components_test.dart",
      "test/home_navigation_shell_test.dart",
      "test/shell_runtime_navigation_test.dart",
      "test/ui_complete_integration_test.dart",
      "test/utility_registry_test.dart",
      "test/figma_complete_contract_test.dart",
      "test/figma_runtime_manifest_test.dart"
    ) `
    -FailureMessage "dart format failed."

  Write-Host "[4/8] Analyze complete project" -ForegroundColor Cyan
  Invoke-CheckedNative `
    -Executable "flutter" `
    -ArgumentList @("analyze") `
    -FailureMessage "flutter analyze failed. No APK was built or installed."

  Write-Host "[5/8] Design, shell and responsive tests" -ForegroundColor Cyan

  $uiTests = @(
    "test/commercial_home_page_test.dart",
    "test/fluviai_responsive_components_test.dart",
    "test/home_navigation_shell_test.dart",
    "test/shell_runtime_navigation_test.dart",
    "test/ui_complete_integration_test.dart",
    "test/utility_registry_test.dart",
    "test/figma_complete_contract_test.dart",
    "test/figma_runtime_manifest_test.dart"
  )

  $testLog = Join-Path $qaDirectory "design_tests_console.txt"

  & flutter test `
    @uiTests `
    --reporter expanded `
    --concurrency=1 2>&1 |
    Tee-Object -FilePath $testLog

  if ($LASTEXITCODE -ne 0) {
    throw (
      "Design integration tests failed. " +
      "No APK was built or installed. See $testLog"
    )
  }

  Write-Host "[6/8] Android debug build" -ForegroundColor Cyan

  if (-not $env:MAPBOX_ACCESS_TOKEN -or
      -not $env:MAPBOX_ACCESS_TOKEN.StartsWith("pk.")) {
    throw "MAPBOX_ACCESS_TOKEN is required and must begin with pk."
  }

  $apk = Join-Path $projectRoot `
    "build\app\outputs\flutter-apk\app-debug.apk"

  if (Test-Path -LiteralPath $apk) {
    Remove-Item -LiteralPath $apk -Force
  }

  $buildStartedUtc = [DateTime]::UtcNow

  Invoke-CheckedNative `
    -Executable "flutter" `
    -ArgumentList @("build", "apk", "--debug") `
    -FailureMessage "Android debug build failed."

  if (-not (Test-Path -LiteralPath $apk)) {
    throw "Build reported success, but APK was not found: $apk"
  }

  $apkInfo = Get-Item -LiteralPath $apk

  if ($apkInfo.LastWriteTimeUtc -lt $buildStartedUtc.AddSeconds(-2)) {
    throw "The APK is stale and was not produced by this validation run."
  }

  $apkHash = (Get-FileHash `
    -LiteralPath $apk `
    -Algorithm SHA256).Hash

  $apkHash | Set-Content `
    -LiteralPath (Join-Path $qaDirectory "app-debug.sha256.txt") `
    -Encoding UTF8

  if ($Install) {
    Write-Host "[7/8] Install and standalone Samsung launch" `
      -ForegroundColor Cyan

    $adb = Resolve-Adb

    if (-not $adb) {
      throw "adb.exe was not found."
    }

    $adbArgs = @()

    if ($DeviceId) {
      $adbArgs += @("-s", $DeviceId)
    }

    $applicationId = Resolve-ApplicationId

    Invoke-CheckedNative `
      -Executable $adb `
      -ArgumentList ($adbArgs + @("devices"))

    Invoke-CheckedNative `
      -Executable $adb `
      -ArgumentList ($adbArgs + @("install", "-r", $apk)) `
      -FailureMessage "ADB install failed."

    Invoke-CheckedNative `
      -Executable $adb `
      -ArgumentList (
        $adbArgs +
        @("shell", "am", "force-stop", $applicationId)
      )

    Invoke-CheckedNative `
      -Executable $adb `
      -ArgumentList ($adbArgs + @("logcat", "-c"))

    Invoke-CheckedNative `
      -Executable $adb `
      -ArgumentList (
        $adbArgs +
        @(
          "shell",
          "monkey",
          "-p",
          $applicationId,
          "-c",
          "android.intent.category.LAUNCHER",
          "1"
        )
      ) `
      -FailureMessage "Standalone launch failed."

    Start-Sleep -Seconds 5

    $appPid = (
      & $adb @adbArgs shell pidof $applicationId
    ).Trim()

    if ($LASTEXITCODE -ne 0 -or -not $appPid) {
      throw "$applicationId did not remain alive after launch."
    }

    Write-Host "[8/8] Capture visual QA evidence" `
      -ForegroundColor Cyan

    $remoteScreenshot = "/sdcard/fluviai_design_home.png"
    $localScreenshot = Join-Path `
      $qaDirectory `
      "home_after_standalone_launch.png"

    Invoke-CheckedNative `
      -Executable $adb `
      -ArgumentList (
        $adbArgs +
        @("shell", "screencap", "-p", $remoteScreenshot)
      )

    Invoke-CheckedNative `
      -Executable $adb `
      -ArgumentList (
        $adbArgs +
        @("pull", $remoteScreenshot, $localScreenshot)
      )

    Invoke-CheckedNative `
      -Executable $adb `
      -ArgumentList (
        $adbArgs +
        @("shell", "rm", $remoteScreenshot)
      )

    $logPath = Join-Path `
      $qaDirectory `
      "logcat_after_standalone_launch.txt"

    & $adb @adbArgs logcat -d -t 1200 |
      Out-File -FilePath $logPath -Encoding utf8

    if ($LASTEXITCODE -ne 0) {
      throw "Could not capture logcat."
    }

    $summary = @(
      "FluviAI Design Integration Gate",
      "Validated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')",
      "Application: $applicationId",
      "PID: $appPid",
      "APK: $apk",
      "APK SHA-256: $apkHash",
      "Screenshot: $localScreenshot",
      "Logcat: $logPath",
      "Design technical gate: PASS",
      "Visual PASS: pending complete manual multi-screen QA",
      "Functional utility gate: intentionally deferred"
    )

    $summary | Set-Content `
      -LiteralPath (
        Join-Path $qaDirectory "validation_summary.txt"
      ) `
      -Encoding UTF8

    Write-Host "Installed and launched $applicationId (pid $appPid)" `
      -ForegroundColor Green
    Write-Host "Screenshot: $localScreenshot" `
      -ForegroundColor Green
    Write-Host "Logcat: $logPath" `
      -ForegroundColor Green
  } else {
    Write-Host "[7/8] Install skipped." -ForegroundColor Yellow
    Write-Host "[8/8] Visual capture skipped." -ForegroundColor Yellow
  }

  Write-Host ""
  Write-Host "FluviAI Design Integration Gate completed." `
    -ForegroundColor Green
  Write-Host (
    "Functional utility tests were intentionally not executed."
  ) -ForegroundColor Yellow
}
catch {
  $_ | Out-String | Tee-Object -FilePath $validationLog -Append
  throw
}
