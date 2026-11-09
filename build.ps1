# Builds and tests everything. Run from anywhere:
#   .\build.ps1
#   .\build.ps1 -FresnelDir C:\path\to\fresnel -LazarusConfig C:\path\to\config
#
# The packages are registered in a copy of the Lazarus configuration under out\lazcfg, so
# building does not change the configuration of the IDE. Pass -LazarusConfig to use (and
# register the packages in) a configuration of your own instead.
param(
  [string]$FresnelDir = (Join-Path $PSScriptRoot '..\..\lazarus_libraries\fresnel'),
  [string]$Lazbuild = $(if ($env:LAZBUILD) { $env:LAZBUILD } else { 'C:\lazarus\lazarus\lazbuild.exe' }),
  [string]$BaseConfig = 'C:\lazarus\config_lazarus',
  [string]$LazarusConfig = ''
)
$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot

if ($LazarusConfig -eq '') {
  $LazarusConfig = Join-Path $Root 'out\lazcfg'
  if (-not (Test-Path $LazarusConfig)) {
    New-Item -ItemType Directory -Force (Split-Path $LazarusConfig) | Out-Null
    Copy-Item $BaseConfig $LazarusConfig -Recurse
  }
}

function Build([string]$Target) {
  $output = & $Lazbuild "--pcp=$LazarusConfig" $Target 2>&1
  if ($LASTEXITCODE -ne 0) {
    $output | Select-Object -Last 30 | ForEach-Object { "$_" }
    throw "Build failed: $Target"
  }
}

# lazbuild writes a copy of its package list to the current folder, so work from elsewhere.
Push-Location $env:TEMP
try {
  $packages = 'ohspluginframework', 'ohspluginframework_fresnel', 'ohspluginframework_ribbon',
              'ohspluginframework_multigrid', 'ohspluginframework_gantt'
  foreach ($p in $packages) {
    & $Lazbuild "--pcp=$LazarusConfig" --add-package-link "$Root\packages\lazarus\$p.lpk" | Out-Null
  }
  foreach ($p in $packages) { Build "$Root\packages\lazarus\$p.lpk" }

  Build "$Root\demo\fresnel\plugins\hello\hello.lpi"
  Build "$Root\demo\fresnel\plugins\floatcheck\floatcheck.lpi"
  Build "$Root\demo\fresnel\host\ohsplugindemo.lpi"
  Build "$Root\test\testframework.lpi"
}
finally {
  Remove-Item packagefiles.xml -ErrorAction SilentlyContinue
  Pop-Location
}

# The demo needs the Skia library that matches its bitness beside it. This compiler is 32 bit.
$Out = "$Root\demo\fresnel\out\i386-win32"
Copy-Item "$FresnelDir\bin\Binary\Shared\Win32\sk4d.dll" $Out -Force

& "$Root\test\testframework.exe" "$Out\plugins"
if ($LASTEXITCODE -ne 0) { throw 'Framework tests failed' }

& "$Out\ohsplugindemo.exe" --selftest | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'Demo self test failed' }

"BUILD OK, TESTS PASSED. Run $Out\ohsplugindemo.exe"
