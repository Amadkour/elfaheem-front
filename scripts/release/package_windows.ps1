<#
Alfaheem for Windows: build, then package the installer and the zip (Learning Hub Phase 8, N2; docs/release/WINDOWS.md).

  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/release/package_windows.ps1 [options]

  -BuildName x.y.z   default NB_BUILD_NAME, else pubspec.yaml's version
  -BuildNumber n     default NB_BUILD_NUMBER, else pubspec.yaml's +n
  -OutDir <dir>      default build/releases/<x.y.z>-<n>/
  -UploadDir <dir>   also copy the installer and the zip there (the workflow's build/nb-upload)
  -SkipBuild         package the Release folder an earlier run built
  -TestApi <url>     a TEST package against a local stack (e.g. http://localhost:41080/api): a --profile build
                     (a release build accepts only an https:// API, resolveApiBaseUrl), written to build/windows-test/,
                     never to build/releases/ and never uploaded

Build flags are scripts/build_release.sh's: --obfuscate, symbols in build/debug-info/<x.y.z>+<n>/windows/ (keep them:
`flutter symbolize -i trace.txt -d <that folder>/app.windows-x64.symbols` is the only way to read a stack trace).
Inno Setup 6 (ISCC.exe) is found through ISCC, PATH or its usual folders; when it is missing it is installed with
winget (user scope), else Chocolatey. Output: Alfaheem-<x.y.z>-<n>-windows-x64-setup.exe and
Alfaheem-<x.y.z>-<n>-windows-x64.zip, each with a .sha256 file, and SHA256SUMS.txt.
#>
param(
  [string]$BuildName = $env:NB_BUILD_NAME,
  [string]$BuildNumber = $env:NB_BUILD_NUMBER,
  [string]$OutDir = '',
  [string]$UploadDir = '',
  [switch]$SkipBuild,
  [string]$TestApi = ''
)
# Continue, not Stop: Windows PowerShell 5.1 turns a native tool's stderr into errors when the output is captured
# (the runner, Codemagic); every step checks its own result instead.
$ErrorActionPreference = 'Continue'
$front = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $front

function Fail([string]$msg) { Write-Host "x $msg"; exit 1 }

# ── version ──────────────────────────────────────────────────────────────────────────────────────────────────────
$pub = Select-String -Path pubspec.yaml -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$' | Select-Object -First 1
if (-not $BuildName) { if ($pub) { $BuildName = $pub.Matches[0].Groups[1].Value } }
if (-not $BuildNumber) { if ($pub) { $BuildNumber = $pub.Matches[0].Groups[2].Value } }
if (-not ($BuildName -match '^[0-9]+\.[0-9]+\.[0-9]+$')) { Fail "the build name must be x.y.z (got '$BuildName')" }
if (-not ($BuildNumber -match '^[0-9]+$')) { Fail "the build number must be a whole number (got '$BuildNumber')" }
$test = [bool]$TestApi
if ($test -and $UploadDir) { Fail '-TestApi packages are never uploaded: drop -UploadDir' }
if (-not $OutDir) {
  if ($test) { $OutDir = 'build/windows-test' } else { $OutDir = "build/releases/$BuildName-$BuildNumber" }
}
$base = "Alfaheem-$BuildName-$BuildNumber-windows-x64"
if ($test) { $base = "$base-TEST" }
$release = Join-Path $front 'build\windows\x64\runner\Release'
if ($test) { $release = Join-Path $front 'build\windows\x64\runner\Profile' }
$symbols = "build/debug-info/$BuildName+$BuildNumber/windows"

# ── Inno Setup ───────────────────────────────────────────────────────────────────────────────────────────────────
function Find-Iscc {
  $c = @()
  if ($env:ISCC) { $c += $env:ISCC }
  $cmd = Get-Command ISCC.exe -ErrorAction SilentlyContinue
  if ($cmd) { $c += $cmd.Source }
  $c += (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe')
  if (${env:ProgramFiles(x86)}) { $c += (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe') }
  $c += (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
  foreach ($p in $c) { if ($p -and (Test-Path $p)) { return $p } }
  return $null
}
$iscc = Find-Iscc
if (-not $iscc) {
  if (Get-Command winget -ErrorAction SilentlyContinue) {
    Write-Host '==> installing Inno Setup (winget, user scope)'
    winget install --id JRSoftware.InnoSetup -e --scope user --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
  } elseif (Get-Command choco -ErrorAction SilentlyContinue) {
    Write-Host '==> installing Inno Setup (Chocolatey)'
    choco install innosetup -y --no-progress
  }
  $iscc = Find-Iscc
}
if (-not $iscc) { Fail 'Inno Setup 6 is missing: winget install JRSoftware.InnoSetup (or set ISCC to ISCC.exe)' }
$innoVer = ''
$innoKey = Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall' -ErrorAction SilentlyContinue |
  Where-Object { $_.PSChildName -like 'Inno Setup 6*' } | Select-Object -First 1
if ($innoKey) { $innoVer = $innoKey.GetValue('DisplayVersion') }
Write-Host "==> Inno Setup $innoVer : $iscc"

# ── build ────────────────────────────────────────────────────────────────────────────────────────────────────────
if (-not $SkipBuild) {
  # (VS 2026's STL1011 on the /await plugins is handled in windows/CMakeLists.txt: no environment variable needed)
  flutter config --enable-windows-desktop | Out-Null
  if ($test) {
    Write-Host "==> flutter build windows --profile against $TestApi (TEST package)"
    flutter build windows --profile "--dart-define=API_BASE_URL=$TestApi" "--build-name=$BuildName" "--build-number=$BuildNumber"
  } else {
    Write-Host "==> flutter build windows --release $BuildName+$BuildNumber"
    New-Item -ItemType Directory -Force $symbols | Out-Null
    flutter build windows --release --obfuscate "--split-debug-info=$symbols" "--build-name=$BuildName" "--build-number=$BuildNumber"
  }
  if ($LASTEXITCODE -ne 0) { Fail "flutter build windows failed ($LASTEXITCODE)" }
}
if (-not (Test-Path (Join-Path $release 'alfaheem.exe'))) { Fail "no alfaheem.exe in $release (build first, or drop -SkipBuild)" }
# the device database (D-1353): sqflite_common_ffi opens sqlite3.dll, which the sqlite3 package's build hook puts
# next to the exe. Without it the app starts but every offline feature fails, so a package without it is refused.
if (-not (Test-Path (Join-Path $release 'sqlite3.dll'))) { Fail "sqlite3.dll is not in $release (the sqlite3 build hook did not run)" }

# ── package ──────────────────────────────────────────────────────────────────────────────────────────────────────
New-Item -ItemType Directory -Force $OutDir | Out-Null
$out = (Resolve-Path $OutDir).Path
$exe = Join-Path $out "$base-setup.exe"
$zip = Join-Path $out "$base.zip"
Remove-Item -Force -ErrorAction SilentlyContinue $exe, $zip

Write-Host '==> installer'
& $iscc /Q "/DAppVersion=$BuildName" "/DAppBuild=$BuildNumber" "/DSourceDir=$release" "/DOutputDir=$out" "/DOutputName=$base-setup" (Join-Path $front 'windows\installer\nextbrain.iss')
if ($LASTEXITCODE -ne 0) { Fail "ISCC failed ($LASTEXITCODE)" }

Write-Host '==> zip'
Compress-Archive -Path (Join-Path $release '*') -DestinationPath $zip -Force -ErrorAction Stop
if (-not $test -and (Test-Path $symbols)) {
  Compress-Archive -Path "$symbols/*" -DestinationPath "build/debug-info-$BuildName+$BuildNumber-windows.zip" -Force -ErrorAction Stop
}

$sums = @()
foreach ($f in @($exe, $zip)) {
  $h = (Get-FileHash -Algorithm SHA256 $f).Hash.ToLower()
  $n = Split-Path $f -Leaf
  [IO.File]::WriteAllText("$f.sha256", "$h  $n`n")
  $sums += "$h  $n"
  Write-Host ("  {0}  {1:N0} bytes  sha256 {2}" -f $n, (Get-Item $f).Length, $h)
}
[IO.File]::WriteAllText((Join-Path $out 'SHA256SUMS.txt'), (($sums -join "`n") + "`n"))

if ($UploadDir) {
  New-Item -ItemType Directory -Force $UploadDir | Out-Null
  Copy-Item -Force $exe, $zip $UploadDir -ErrorAction Stop
  Write-Host "==> copied to $UploadDir"
}
Write-Host "done: $out"
