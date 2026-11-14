param(
  [string]$Repo = "xbghc/mason-win-arm64",
  [switch]$CheckOnly,
  [switch]$ForceRebuild,
  [switch]$Publish
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path "$PSScriptRoot\..").Path
$distDir = "$root\dist"

$syncOut = New-TemporaryFile
try {
  $env:GITHUB_OUTPUT = $syncOut.FullName
  $syncArgs = @("$root\scripts\sync-upstream.py", "--repo", $Repo, "--respect-local-toolchains")
  if ($CheckOnly) {
    $syncArgs += "--check-only"
  } elseif ($ForceRebuild) {
    $syncArgs += "--force-rebuild"
  } else {
    $syncArgs += "--download-reusable"
  }

  & python @syncArgs
  if ($LASTEXITCODE -ne 0) { throw "sync-upstream.py failed ($LASTEXITCODE)" }

  if ($CheckOnly) { exit 0 }

  $outputs = @{}
  foreach ($line in (Get-Content $syncOut.FullName)) {
    if ($line -match "^([^=]+)=(.*)$") {
      $outputs[$matches[1]] = $matches[2]
    }
  }

  if ($outputs["needs_publish"] -ne "true") {
    Write-Host "All packages are already up to date with upstream and published in the latest release."
    exit 0
  }

  $tag = $outputs["release_tag"]
  Write-Host "`n>>> Fetching sources for updated/missing packages..."
  & pwsh -NoProfile -File "$root\scripts\fetch-sources.ps1" -NoVendor
  if ($LASTEXITCODE -ne 0) { throw "fetch-sources.ps1 failed" }

  Write-Host "`n>>> Building native win_arm64 binaries..."
  & pwsh -NoProfile -File "$root\scripts\build-all-native.ps1"
  if ($LASTEXITCODE -ne 0) { throw "build-all-native.ps1 failed" }

  Write-Host "`n>>> Packing Mason registry for tag $tag..."
  & python "$root\scripts\pack-registry.py" --repo $Repo --tag $tag
  if ($LASTEXITCODE -ne 0) { throw "pack-registry.py failed" }

  if ($Publish) {
    Write-Host "`n>>> Publishing GitHub Release $tag..."
    $zips = Get-ChildItem "$distDir\*.zip" | ForEach-Object { $_.FullName }
    & gh release create $tag @zips "$distDir\checksums.txt" `
      --repo $Repo `
      --title $tag `
      --notes-file "$distDir\release-notes.md"
    if ($LASTEXITCODE -ne 0) { throw "gh release create failed" }
  } else {
    Write-Host "`nBuild & registry packaging succeeded in dist/ (tag: $tag). Re-run with -Publish or push to let GitHub Actions release."
  }
} finally {
  Remove-Item Env:\GITHUB_OUTPUT -ErrorAction SilentlyContinue
  Remove-Item $syncOut.FullName -Force -ErrorAction SilentlyContinue
}
