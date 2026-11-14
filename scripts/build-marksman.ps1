$ErrorActionPreference = "Stop"
$root = (Resolve-Path "$PSScriptRoot\..").Path
$buildDir = "$root\.build"
$distDir = "$root\dist"
$versions = Get-Content -Raw -Encoding utf8 "$root\versions.json" | ConvertFrom-Json

$marksmanVer = $versions.marksman.version
$marksmanRepo = $versions.marksman.repo
$marksmanZip = $versions.marksman.artifact.Replace("{version}", $marksmanVer)

if (Test-Path "$distDir\$marksmanZip") {
  Write-Host "=== marksman $marksmanVer already exists in dist\$marksmanZip ==="
  exit 0
}

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
  throw ".NET SDK (dotnet) is not installed in PATH. Install Microsoft.DotNet.SDK.9 via winget to compile marksman natively for win-arm64."
}

New-Item -ItemType Directory -Force $buildDir, $distDir | Out-Null
$marker = "$buildDir\marksman\.mason-version"
if (Test-Path "$buildDir\marksman") {
  $cur = if (Test-Path $marker) { (Get-Content -Raw $marker).Trim() } else { "" }
  if ($cur -ne $marksmanVer) {
    Remove-Item -Recurse -Force "$buildDir\marksman"
  }
}
if (-not (Test-Path "$buildDir\marksman")) {
  git clone --depth 1 --branch $marksmanVer "https://github.com/$marksmanRepo.git" "$buildDir\marksman"
  if ($LASTEXITCODE -ne 0) { throw "git clone marksman@$marksmanVer failed" }
  Set-Content -Encoding utf8 -NoNewline -Path $marker -Value $marksmanVer
}

Push-Location "$buildDir\marksman"
try {
  if (Test-Path "global.json") { Remove-Item "global.json" -Force }
  $env:DOTNET_ROLL_FORWARD = "LatestMajor"
  $stage = "$buildDir\stage-marksman"
  if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
  dotnet publish Marksman/Marksman.fsproj -c Release -r win-arm64 --self-contained true `
    -p:RollForward=LatestMajor `
    -p:PublishSingleFile=true -p:PublishTrimmed=false `
    -p:IncludeNativeLibrariesForSelfExtract=true -p:EnableCompressionInSingleFile=true `
    -o $stage
  if ($LASTEXITCODE -ne 0) { throw "dotnet publish marksman failed ($LASTEXITCODE)" }

  $pe = & "$root\scripts\verify-pe.ps1" -Path "$stage\marksman.exe"
  Write-Host "marksman $marksmanVer Arch: $($pe.Arch) ($($pe.Machine))"
  if ($pe.Arch -ne "ARM64") { throw "marksman is not ARM64!" }

  python -c "import zipfile; z=zipfile.ZipFile(r'$distDir\$marksmanZip','w',zipfile.ZIP_DEFLATED); z.write(r'$stage\marksman.exe','marksman.exe'); z.close()"
  if ($LASTEXITCODE -ne 0) { throw "Failed to zip $marksmanZip" }
  Write-Host "Packaged dist\$marksmanZip"
} finally {
  Pop-Location
}
