# Recursively walks the PE import tables (dumpbin /dependents) starting from
# the plugin binary and fails if any imported DLL is neither present next to
# the plugin nor a Windows system DLL. Prints the resolved closure.
param(
  [Parameter(Mandatory)] [string] $Dir,
  [Parameter(Mandatory)] [string] $Binary
)
$ErrorActionPreference = 'Stop'

$dumpbin = Get-Command dumpbin -ErrorAction SilentlyContinue | ForEach-Object Source
if (-not $dumpbin) {
  $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
  $vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
  $dumpbin = Get-ChildItem "$vs\VC\Tools\MSVC\*\bin\Hostx64\x64\dumpbin.exe" | Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $dumpbin) { Write-Error 'dumpbin.exe not found'; exit 1 }

$system32 = Join-Path $env:SystemRoot 'System32'
function Test-SystemDll([string] $name) {
  if ($name -match '^(api|ext)-ms-') { return $true }
  # The VC++ redistributable is present on build runners but not guaranteed on user machines.
  if ($name -match '^(vcruntime|msvcp|concrt|vcomp|vccorlib)\d') { return $false }
  return Test-Path (Join-Path $system32 $name)
}

$local = @{}
Get-ChildItem $Dir -File | ForEach-Object { $local[$_.Name.ToLowerInvariant()] = $_.FullName }

$queue = [System.Collections.Generic.Queue[string]]::new()
$seen = @{}
$missing = [ordered]@{}
$queue.Enqueue($Binary)
$seen[$Binary.ToLowerInvariant()] = $true

while ($queue.Count) {
  $current = $queue.Dequeue()
  $path = $local[$current.ToLowerInvariant()]
  if (-not $path) { Write-Error "$current not found in $Dir"; exit 1 }

  $headers = & $dumpbin /nologo /headers $path | Out-String
  if ($headers -notmatch 'machine \(x64\)') { Write-Host "::error::$current is not an x64 image"; exit 1 }

  $imports = & $dumpbin /nologo /dependents $path |
    Where-Object { $_ -match '^\s+(\S+\.dll)\s*$' } | ForEach-Object { $Matches[1] }
  foreach ($imp in $imports) {
    $key = $imp.ToLowerInvariant()
    if ($local.ContainsKey($key)) {
      if (-not $seen[$key]) { $seen[$key] = $true; $queue.Enqueue($imp) }
    } elseif (-not (Test-SystemDll $imp)) {
      $missing[$imp] = @(@($missing[$imp]) + $current | Where-Object { $_ })
    }
  }
}

Write-Host "Resolved $($seen.Count) bundled image(s):"
$seen.Keys | Sort-Object | ForEach-Object { Write-Host "  $_" }

$unused = $local.Keys | Where-Object { $_ -like '*.dll' -and -not $seen[$_] }
if ($unused) { Write-Host "Bundled but not referenced: $($unused -join ', ')" }

if ($missing.Count) {
  foreach ($k in $missing.Keys) { Write-Host "::error::Missing $k (imported by $($missing[$k] -join ', '))" }
  exit 1
}
Write-Host 'All non-system dependencies are bundled.'
