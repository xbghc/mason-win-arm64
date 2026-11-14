param(
  [switch]$NoVendor,
  [switch]$Force,
  [switch]$IncludeMarksman
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path "$PSScriptRoot\..").Path
$buildDir = "$root\.build"
$distDir = "$root\dist"
$versions = Get-Content -Raw -Encoding utf8 "$root\versions.json" | ConvertFrom-Json

New-Item -ItemType Directory -Force $buildDir | Out-Null

function Ensure-ClonedTag {
  param(
    [string]$Name,
    [string]$Repo,
    [string]$Tag,
    [string]$TargetDir,
    [switch]$Submodules
  )
  $marker = "$TargetDir\.mason-version"
  if (Test-Path $TargetDir) {
    $cur = if (Test-Path $marker) { (Get-Content -Raw $marker).Trim() } else { "" }
    if ($cur -ne $Tag) {
      Write-Host "[$Name] Version changed ($cur -> $Tag), refreshing source tree..."
      Remove-Item -Recurse -Force $TargetDir
    }
  }
  if (-not (Test-Path $TargetDir)) {
    $cloneArgs = @("clone", "--depth", "1", "--branch", $Tag)
    if ($Submodules) {
      $cloneArgs += @("--recurse-submodules", "--shallow-submodules")
    }
    $cloneArgs += @("https://github.com/$Repo.git", $TargetDir)
    & git @cloneArgs
    if ($LASTEXITCODE -ne 0) { throw "git clone failed for $Repo@$Tag" }
    Set-Content -Encoding utf8 -NoNewline -Path $marker -Value $Tag
  }
}

# 1. shfmt (mvdan/sh)
$shVer = $versions.shfmt.version
$shZip = $versions.shfmt.artifact.Replace("{version}", $shVer)
if ($Force -or -not (Test-Path "$distDir\$shZip")) {
  Write-Host "=== [1/4] Fetching $($versions.shfmt.repo) $shVer ==="
  Ensure-ClonedTag -Name "shfmt" -Repo $versions.shfmt.repo -Tag $shVer -TargetDir "$buildDir\sh"
  if (-not $NoVendor) {
    Push-Location "$buildDir\sh"
    try {
      go mod vendor
      if ($LASTEXITCODE -ne 0) { throw "go mod vendor failed" }
    } finally {
      Pop-Location
    }
  }
} else {
  Write-Host "=== [1/4] Skipping shfmt $shVer fetch (already present in dist/) ==="
}

# 2. stylua (JohnnyMorganz/StyLua)
$styluaVer = $versions.stylua.version
$styluaZip = $versions.stylua.artifact.Replace("{version}", $styluaVer)
if ($Force -or -not (Test-Path "$distDir\$styluaZip")) {
  Write-Host "=== [2/4] Fetching $($versions.stylua.repo) $styluaVer ==="
  Ensure-ClonedTag -Name "stylua" -Repo $versions.stylua.repo -Tag $styluaVer -TargetDir "$buildDir\stylua"
  if (-not $NoVendor) {
    Push-Location "$buildDir\stylua"
    try {
      New-Item -ItemType Directory -Force ".cargo" | Out-Null
      $vendorCfg = cargo vendor vendor
      if ($LASTEXITCODE -ne 0) { throw "cargo vendor failed" }
      $vendorCfg | Set-Content -Encoding utf8 ".cargo\config.toml"
    } finally {
      Pop-Location
    }
  }
} else {
  Write-Host "=== [2/4] Skipping stylua $styluaVer fetch (already present in dist/) ==="
}

# 3. lua-language-server (LuaLS/lua-language-server)
$lualsVer = $versions.'lua-language-server'.version
$lualsZip = $versions.'lua-language-server'.artifact.Replace("{version}", $lualsVer)
if ($Force -or -not (Test-Path "$distDir\$lualsZip")) {
  Write-Host "=== [3/4] Fetching $($versions.'lua-language-server'.repo) $lualsVer ==="
  Ensure-ClonedTag -Name "lua-language-server" -Repo $versions.'lua-language-server'.repo -Tag $lualsVer -TargetDir "$buildDir\luals" -Submodules
} else {
  Write-Host "=== [3/4] Skipping lua-language-server $lualsVer fetch (already present in dist/) ==="
}

# 4. marksman (artempyanykh/marksman) - fetched when dotnet is available or -IncludeMarksman is set
$marksmanVer = $versions.marksman.version
$marksmanZip = $versions.marksman.artifact.Replace("{version}", $marksmanVer)
$hasDotnet = [bool](Get-Command dotnet -ErrorAction SilentlyContinue)
if (($IncludeMarksman -or $hasDotnet) -and ($Force -or -not (Test-Path "$distDir\$marksmanZip"))) {
  Write-Host "=== [4/4] Fetching $($versions.marksman.repo) $marksmanVer ==="
  Ensure-ClonedTag -Name "marksman" -Repo $versions.marksman.repo -Tag $marksmanVer -TargetDir "$buildDir\marksman"
} else {
  Write-Host "=== [4/4] Skipping marksman $marksmanVer fetch ==="
}

Write-Host "=== SOURCE FETCH COMPLETE ==="
