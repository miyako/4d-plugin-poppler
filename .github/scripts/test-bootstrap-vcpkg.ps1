$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$bootstrapScript = Join-Path $PSScriptRoot 'bootstrap-vcpkg.ps1'
$fixture = Join-Path ([System.IO.Path]::GetTempPath()) "poppler-bootstrap-test-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $fixture | Out-Null
$savedFailures = $env:BOOTSTRAP_TEST_FAILURES
$savedMissing = $env:BOOTSTRAP_TEST_MISSING

function Assert($Condition, [string] $Message) {
  if (-not $Condition) { throw $Message }
}

# Keep backoff assertions deterministic and fast without mocking native exits.
function Start-Sleep([int] $Seconds) {
  $delays.Add($Seconds)
}

try {
  $bootstrap = Join-Path $fixture 'bootstrap-vcpkg.bat'
  if ($IsWindows) {
    @'
@echo off
setlocal
set /a count=0
if exist "%~dp0attempts.txt" set /p count=<"%~dp0attempts.txt"
set /a count+=1
>"%~dp0attempts.txt" echo %count%
if %count% LEQ %BOOTSTRAP_TEST_FAILURES% exit /b 23
if "%BOOTSTRAP_TEST_MISSING%"=="0" >"%~dp0vcpkg.exe" echo fixture
exit /b 0
'@ | Set-Content $bootstrap
  } else {
    @'
#!/bin/sh
root="$(dirname "$0")"
count=0
if [ -f "$root/attempts.txt" ]; then read -r count < "$root/attempts.txt"; fi
count=$((count + 1))
printf '%s\n' "$count" > "$root/attempts.txt"
if [ "$count" -le "$BOOTSTRAP_TEST_FAILURES" ]; then exit 23; fi
if [ "$BOOTSTRAP_TEST_MISSING" = 0 ]; then printf fixture > "$root/vcpkg.exe"; fi
exit 0
'@ | Set-Content $bootstrap
    & chmod +x $bootstrap
    if ($LASTEXITCODE -ne 0) { throw 'Could not make bootstrap fixture executable' }
  }

  $cases = @(
    @{ Name = 'immediate success'; Failures = 0; Missing = 0; Attempts = 1; Delays = ''; Error = $null },
    @{ Name = 'transient failure then success'; Failures = 2; Missing = 0; Attempts = 3; Delays = '10,20'; Error = $null },
    @{ Name = 'success on final attempt'; Failures = 3; Missing = 0; Attempts = 4; Delays = '10,20,40'; Error = $null },
    @{ Name = 'retry exhaustion'; Failures = 4; Missing = 0; Attempts = 4; Delays = '10,20,40'; Error = 'Bootstrap exit code: 23' },
    @{ Name = 'failed bootstrap with stale executable'; Failures = 4; Missing = 0; Stale = $true; Attempts = 4; Delays = '10,20,40'; Error = 'Bootstrap exit code: 23' },
    @{ Name = 'success without executable'; Failures = 0; Missing = 1; Attempts = 4; Delays = '10,20,40'; Error = 'vcpkg.exe present: False' }
  )
  foreach ($case in $cases) {
    foreach ($name in 'attempts.txt', 'vcpkg.exe') {
      $path = Join-Path $fixture $name
      if (Test-Path $path) { Remove-Item $path }
    }
    if ($case.Stale) { Set-Content (Join-Path $fixture 'vcpkg.exe') 'stale fixture' }
    $env:BOOTSTRAP_TEST_FAILURES = [string] $case.Failures
    $env:BOOTSTRAP_TEST_MISSING = [string] $case.Missing
    $delays = [System.Collections.Generic.List[int]]::new()
    $caught = $null
    $installReached = $false
    try {
      & $bootstrapScript -VcpkgRoot $fixture
      $installReached = $true
    } catch {
      $caught = $_.Exception.Message
    }
    Assert ((Get-Content (Join-Path $fixture 'attempts.txt')) -eq $case.Attempts) "$($case.Name): wrong attempt count; error '$caught'"
    Assert (($delays -join ',') -eq $case.Delays) "$($case.Name): wrong backoff"
    if ($case.Error) {
      Assert ($caught -like "*$($case.Error)*") "$($case.Name): expected final error, got '$caught'"
      Assert ($caught -like '*failed after 4 attempts*') "$($case.Name): expected retry exhaustion"
      Assert (-not $installReached) "$($case.Name): install must not be reached"
    } else {
      Assert ($null -eq $caught -and $installReached) "$($case.Name): unexpected failure '$caught'"
    }
    Assert $PSNativeCommandUseErrorActionPreference 'Caller native error preference was changed'
    Write-Host "PASS: $($case.Name)"
  }

  Remove-Item $bootstrap
  $delays.Clear()
  $caught = $null
  try {
    & $bootstrapScript -VcpkgRoot $fixture
  } catch {
    $caught = $_.Exception.Message
  }
  Assert ($null -ne $caught) 'Missing bootstrap command must fail immediately'
  Assert ($delays.Count -eq 0) 'Missing bootstrap command must not be retried'
  Write-Host 'PASS: missing bootstrap command fails fast'
} finally {
  $env:BOOTSTRAP_TEST_FAILURES = $savedFailures
  $env:BOOTSTRAP_TEST_MISSING = $savedMissing
  Remove-Item $fixture -Recurse -Force
}
