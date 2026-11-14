$ErrorActionPreference = "Stop"
$root = (Resolve-Path "$PSScriptRoot\..").Path
$buildDir = "$root\.build"
$distDir = "$root\dist"
$cacheDir = "$root\.cache"
$vcvars = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat"

New-Item -ItemType Directory -Force $distDir, "$cacheDir\go-build", "$cacheDir\gopath", "$cacheDir\cargo", "$cacheDir\tmp" | Out-Null
$env:TEMP = "$cacheDir\tmp"
$env:TMP = "$cacheDir\tmp"

# ==============================================================================
# 1. shfmt v3.14.1 (Go 1.26.0 windows/arm64)
# ==============================================================================
if (-not (Test-Path "$distDir\shfmt-v3.14.1-win-arm64.zip")) {
  Write-Host "=== [1/3] Building shfmt v3.14.1 (windows/arm64) ==="
  Push-Location "$buildDir\sh"
  try {
    git checkout -- go.mod 2>$null
    $go126 = "$env:USERPROFILE\go\pkg\mod\golang.org\toolchain@v0.0.1-go1.26.0.windows-arm64"
    $goExe = if (Test-Path "$go126\bin\go.exe") {
      $env:GOROOT = $go126
      "$go126\bin\go.exe"
    } else {
      "go"
    }
    $env:GOOS = "windows"
    $env:GOARCH = "arm64"
    $env:CGO_ENABLED = "0"
    $env:GOTOOLCHAIN = "local"
    $env:GOCACHE = "$cacheDir\go-build"
    $env:GOPATH = "$cacheDir\gopath"

    $stageSh = "$buildDir\stage-shfmt"
    New-Item -ItemType Directory -Force $stageSh | Out-Null
    & $goExe build -mod=vendor -trimpath -ldflags="-s -w -X main.version=v3.14.1" -o "$stageSh\shfmt.exe" ./cmd/shfmt
    if ($LASTEXITCODE -ne 0) { throw "go build shfmt failed ($LASTEXITCODE)" }

    $ver = & "$stageSh\shfmt.exe" --version
    $pe = & "$root\scripts\verify-pe.ps1" -Path "$stageSh\shfmt.exe"
    Write-Host "shfmt version: $ver | Arch: $($pe.Arch) ($($pe.Machine))"
    if ($pe.Arch -ne "ARM64") { throw "shfmt is not ARM64!" }

    python -c "import zipfile; z=zipfile.ZipFile(r'$distDir\shfmt-v3.14.1-win-arm64.zip','w',zipfile.ZIP_DEFLATED); z.write(r'$stageSh\shfmt.exe','shfmt.exe'); z.close()"
    Write-Host "Packaged dist\shfmt-v3.14.1-win-arm64.zip"
  } finally {
    Remove-Item Env:\GOROOT -ErrorAction SilentlyContinue
    Pop-Location
  }
}

# ==============================================================================
# 2. stylua v2.6.0 (Rust aarch64-pc-windows-msvc)
# ==============================================================================
if (-not (Test-Path "$distDir\stylua-v2.6.0-win-arm64.zip")) {
  Write-Host "=== [2/3] Building stylua v2.6.0 (aarch64-pc-windows-msvc) ==="
  $env:CARGO_HOME = "$cacheDir\cargo"
  cmd /c "`"$vcvars`" arm64 && cd /d `"$buildDir\stylua`" && cargo build --release --offline --features `"lua52,lua53,lua54,luajit,luau`""
  if ($LASTEXITCODE -ne 0) { throw "cargo build stylua failed ($LASTEXITCODE)" }

  $styluaExe = "$buildDir\stylua\target\release\stylua.exe"
  $ver = & $styluaExe --version
  $pe = & "$root\scripts\verify-pe.ps1" -Path $styluaExe
  Write-Host "stylua version: $ver | Arch: $($pe.Arch) ($($pe.Machine))"
  if ($pe.Arch -ne "ARM64") { throw "stylua is not ARM64!" }

  python -c "import zipfile; z=zipfile.ZipFile(r'$distDir\stylua-v2.6.0-win-arm64.zip','w',zipfile.ZIP_DEFLATED); z.write(r'$styluaExe','stylua.exe'); z.close()"
  Write-Host "Packaged dist\stylua-v2.6.0-win-arm64.zip"
}

# ==============================================================================
# 3. lua-language-server 3.19.2 (C++17 / luamake / MSVC ARM64)
# ==============================================================================
if (-not (Test-Path "$distDir\lua-language-server-3.19.2-win32-arm64.zip")) {
  Write-Host "=== [3/3] Building lua-language-server 3.19.2 (win32-arm64) ==="
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
dst = r'$distDir\lua-language-server-3.19.2-win32-arm64.zip'
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

Write-Host "=== ALL NATIVE ARM64 BUILDS SUCCEEDED ==="
