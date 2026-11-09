param(
  [Parameter(Mandatory)] [string] $VcpkgRoot
)
$ErrorActionPreference = 'Stop'
# Native failures must reach the explicit exit-code checks, even if the caller
# enables PowerShell's native-command error preference.
$PSNativeCommandUseErrorActionPreference = $false

$bootstrap = Join-Path $VcpkgRoot 'bootstrap-vcpkg.bat'
$executable = Join-Path $VcpkgRoot 'vcpkg.exe'
$maxAttempts = 4
for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
  Write-Host "Bootstrapping vcpkg (attempt $attempt/$maxAttempts)"
  & $bootstrap -disableMetrics
  $bootstrapExitCode = $LASTEXITCODE
  if ($bootstrapExitCode -eq 0 -and (Test-Path $executable -PathType Leaf)) {
    return
  }

  $failure = "Bootstrap exit code: $bootstrapExitCode; vcpkg.exe present: $(Test-Path $executable -PathType Leaf)"
  if ($attempt -eq $maxAttempts) {
    throw "vcpkg bootstrap failed after $maxAttempts attempts. $failure"
  }

  $delay = 10 * [math]::Pow(2, $attempt - 1)
  Write-Warning "$failure. Retrying in $delay seconds."
  Start-Sleep -Seconds $delay
}
