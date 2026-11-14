$ErrorActionPreference = "Stop"
$root = (Resolve-Path "$PSScriptRoot\..").Path
$buildDir = "$root\.build"
$distDir = "$root\dist"
$cacheDir = "$root\.cache"
$versions = Get-Content -Raw -Encoding utf8 "$root\versions.json" | ConvertFrom-Json

function Find-VcVarsAll {
  $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
  if (Test-Path $vswhere) {
    $found = & $vswhere -latest -products * -find "VC\Auxiliary\Build\vcvarsall.bat" | Select-Object -First 1
    if ($found -and (Test-Path $found)) {
      return $found
    }
  }
  $fallbacks = @(
    "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvarsall.bat",
    "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat",
    "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat",
    "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat"
  )
  foreach ($candidate in $fallbacks) {
    if (Test-Path $candidate) { return $candidate }
  }
  throw "Could not locate Visual Studio vcvarsall.bat (MSVC ARM64 required)."
}

New-Item -ItemType Directory -Force $distDir, "$cacheDir\go-build", "$cacheDir\gopath", "$cacheDir\tmp" | Out-Null
$origTemp = $env:TEMP
$origTmp = $env:TMP
$env:TEMP = "$cacheDir\tmp"
$env:TMP = "$cacheDir\tmp"

try {
  # ==============================================================================
  # 1. shfmt (Go windows/arm64)
  # ==============================================================================
  $shVer = $versions.shfmt.version
  $shZip = $versions.shfmt.artifact.Replace("{version}", $shVer)
  if (-not (Test-Path "$distDir\$shZip")) {
    Write-Host "=== [1/4] Building shfmt $shVer (windows/arm64) ==="
    Push-Location "$buildDir\sh"
    try {
      git checkout -- go.mod 2>$null
      $hasVendor = Test-Path "$buildDir\sh\vendor"
      $cachedTc = Get-ChildItem "$env:USERPROFILE\go\pkg\mod\golang.org" -Filter "toolchain@*windows-arm64" -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
      $goExe = "go"
      if ($hasVendor -and $cachedTc -and (Test-Path "$($cachedTc.FullName)\bin\go.exe")) {
        $env:GOROOT = $cachedTc.FullName
        $env:GOTOOLCHAIN = "local"
        $goExe = "$($cachedTc.FullName)\bin\go.exe"
      } else {
        $env:GOTOOLCHAIN = "auto"
      }
      $env:GOOS = "windows"
      $env:GOARCH = "arm64"
      $env:CGO_ENABLED = "0"
      $env:GOCACHE = "$cacheDir\go-build"

      $stageSh = "$buildDir\stage-shfmt"
      New-Item -ItemType Directory -Force $stageSh | Out-Null
      $modArgs = if ($hasVendor) { @("-mod=vendor") } else { @() }
      & $goExe build @modArgs -trimpath -ldflags="-s -w -X main.version=$shVer" -o "$stageSh\shfmt.exe" ./cmd/shfmt
      if ($LASTEXITCODE -ne 0) { throw "go build shfmt failed ($LASTEXITCODE)" }

      $ver = & "$stageSh\shfmt.exe" --version
      $pe = & "$root\scripts\verify-pe.ps1" -Path "$stageSh\shfmt.exe"
      Write-Host "shfmt version: $ver | Arch: $($pe.Arch) ($($pe.Machine))"
      if ($pe.Arch -ne "ARM64") { throw "shfmt is not ARM64!" }

      python -c "import zipfile; z=zipfile.ZipFile(r'$distDir\$shZip','w',zipfile.ZIP_DEFLATED); z.write(r'$stageSh\shfmt.exe','shfmt.exe'); z.close()"
      if ($LASTEXITCODE -ne 0) { throw "Failed to zip $shZip" }
      Write-Host "Packaged dist\$shZip"
    } finally {
      Remove-Item Env:\GOROOT -ErrorAction SilentlyContinue
      Remove-Item Env:\GOTOOLCHAIN -ErrorAction SilentlyContinue
      Pop-Location
    }
  }

  # ==============================================================================
  # 2. stylua (Rust aarch64-pc-windows-msvc)
  # ==============================================================================
  $styluaVer = $versions.stylua.version
  $styluaZip = $versions.stylua.artifact.Replace("{version}", $styluaVer)
  if (-not (Test-Path "$distDir\$styluaZip")) {
    Write-Host "=== [2/4] Building stylua $styluaVer (aarch64-pc-windows-msvc) ==="
    $vcvars = Find-VcVarsAll
    $offlineFlag = if (Test-Path "$buildDir\stylua\.cargo\config.toml") { "--offline" } else { "" }
    cmd /c "`"$vcvars`" arm64 && cd /d `"$buildDir\stylua`" && cargo build --release --target aarch64-pc-windows-msvc $offlineFlag --features `"lua52,lua53,lua54,luajit,luau`""
    if ($LASTEXITCODE -ne 0) { throw "cargo build stylua failed ($LASTEXITCODE)" }

    $styluaExe = "$buildDir\stylua\target\aarch64-pc-windows-msvc\release\stylua.exe"
    $ver = & $styluaExe --version
    $pe = & "$root\scripts\verify-pe.ps1" -Path $styluaExe
    Write-Host "stylua version: $ver | Arch: $($pe.Arch) ($($pe.Machine))"
    if ($pe.Arch -ne "ARM64") { throw "stylua is not ARM64!" }

    python -c "import zipfile; z=zipfile.ZipFile(r'$distDir\$styluaZip','w',zipfile.ZIP_DEFLATED); z.write(r'$styluaExe','stylua.exe'); z.close()"
    if ($LASTEXITCODE -ne 0) { throw "Failed to zip $styluaZip" }
    Write-Host "Packaged dist\$styluaZip"
  }

  # ==============================================================================
  # 3. lua-language-server (C++17 / luamake / MSVC ARM64)
  # ==============================================================================
  $lualsVer = $versions.'lua-language-server'.version
  $lualsZip = $versions.'lua-language-server'.artifact.Replace("{version}", $lualsVer)
  if (-not (Test-Path "$distDir\$lualsZip")) {
    Write-Host "=== [3/4] Building lua-language-server $lualsVer (win32-arm64) ==="
    $vcvars = Find-VcVarsAll
    cmd /c "`"$vcvars`" arm64 && cd /d `"$buildDir\luals\3rd\luamake`" && call compile\build.bat notest && cd /d `"$buildDir\luals`" && 3rd\luamake\luamake.exe -notest -fast_setjmp off"
    if ($LASTEXITCODE -ne 0) { throw "luamake build lua-language-server failed ($LASTEXITCODE)" }

    $lualsExe = "$buildDir\luals\bin\lua-language-server.exe"
    $ver = & $lualsExe --version
    $pe = & "$root\scripts\verify-pe.ps1" -Path $lualsExe
    Write-Host "lua-language-server version: $ver | Arch: $($pe.Arch) ($($pe.Machine))"
    if ($pe.Arch -ne "ARM64") { throw "lua-language-server is not ARM64!" }

    $pyPack = @"
import os, zipfile
src = r'$buildDir\luals'
dst = r'$distDir\$lualsZip'
items = ['main.lua', 'debugger.lua', 'LICENSE', 'changelog.md', 'locale', 'meta', 'script', 'bin']
with zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED) as zf:
    for item in items:
        p = os.path.join(src, item)
        if os.path.isfile(p):
            zf.write(p, item)
        elif os.path.isdir(p):
            for root, dirs, files in os.walk(p):
                dirs[:] = [d for d in dirs if d != '.git']
                for fn in files:
                    if fn == '.git' or fn.endswith('.pdb'):
                        continue
                    fp = os.path.join(root, fn)
                    arc = os.path.relpath(fp, src).replace('\\', '/')
                    zf.write(fp, arc)
print('Packed', dst)
"@
    $pyPack | python -
    if ($LASTEXITCODE -ne 0) { throw "Failed to pack lua-language-server zip" }
  }

  # ==============================================================================
  # 4. marksman (F# / .NET SDK win-arm64, built automatically when dotnet exists)
  # ==============================================================================
  $marksmanVer = $versions.marksman.version
  $marksmanZip = $versions.marksman.artifact.Replace("{version}", $marksmanVer)
  if (-not (Test-Path "$distDir\$marksmanZip")) {
    if (Get-Command dotnet -ErrorAction SilentlyContinue) {
      Write-Host "=== [4/4] Building marksman $marksmanVer (win-arm64) ==="
      & "$root\scripts\build-marksman.ps1"
    } else {
      Write-Host "=== [4/4] Skipping marksman $marksmanVer (.NET SDK not installed locally) ==="
    }
  }
} finally {
  $env:TEMP = $origTemp
  $env:TMP = $origTmp
}

Write-Host "=== ALL NATIVE ARM64 BUILDS SUCCEEDED ==="
