$ErrorActionPreference = "Stop"
$root = (Resolve-Path "$PSScriptRoot\..").Path
$buildDir = "$root\.build"
$distDir = "$root\dist"

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
  throw ".NET SDK (dotnet) is not installed in PATH. Install Microsoft.DotNet.SDK.9 via winget to compile marksman natively for win-arm64."
}

New-Item -ItemType Directory -Force $buildDir, $distDir | Out-Null
if (-not (Test-Path "$buildDir\marksman")) {
  git clone --depth 1 --branch 2026-02-08 https://github.com/artempyanykh/marksman.git "$buildDir\marksman"
}

Push-Location "$buildDir\marksman"
try {
  if (Test-Path "global.json") { Remove-Item "global.json" -Force }
  $stage = "$buildDir\stage-marksman"
  if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
  dotnet publish Marksman/Marksman.fsproj -c Release -r win-arm64 --self-contained true `
    -p:PublishSingleFile=true -p:PublishTrimmed=false `
    -p:IncludeNativeLibrariesForSelfExtract=true -p:EnableCompressionInSingleFile=true `
    -o $stage
  if ($LASTEXITCODE -ne 0) { throw "dotnet publish marksman failed ($LASTEXITCODE)" }

  $pe = & "$root\scripts\verify-pe.ps1" -Path "$stage\marksman.exe"
  Write-Host "marksman Arch: $($pe.Arch) ($($pe.Machine))"
  if ($pe.Arch -ne "ARM64") { throw "marksman is not ARM64!" }

  python -c "import zipfile; z=zipfile.ZipFile(r'$distDir\marksman-2026-02-08-win-arm64.zip','w',zipfile.ZIP_DEFLATED); z.write(r'$stage\marksman.exe','marksman.exe'); z.close()"
  Write-Host "Packaged dist\marksman-2026-02-08-win-arm64.zip"
} finally {
  Pop-Location
}
