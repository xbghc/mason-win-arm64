$ErrorActionPreference = "Stop"
$root = (Resolve-Path "$PSScriptRoot\..").Path
$buildDir = "$root\.build"
New-Item -ItemType Directory -Force $buildDir | Out-Null

Write-Host "=== [1/3] Fetching mvdan/sh v3.14.1 ==="
if (-not (Test-Path "$buildDir\sh")) {
  git clone --depth 1 --branch v3.14.1 https://github.com/mvdan/sh.git "$buildDir\sh"
}
Push-Location "$buildDir\sh"
go mod vendor
Pop-Location

Write-Host "=== [2/3] Fetching JohnnyMorganz/StyLua v2.6.0 ==="
if (-not (Test-Path "$buildDir\stylua")) {
  git clone --depth 1 --branch v2.6.0 https://github.com/JohnnyMorganz/StyLua.git "$buildDir\stylua"
}
Push-Location "$buildDir\stylua"
New-Item -ItemType Directory -Force ".cargo" | Out-Null
$vendorCfg = cargo vendor vendor
$vendorCfg | Set-Content -Encoding utf8 ".cargo\config.toml"
Pop-Location

Write-Host "=== [3/3] Fetching LuaLS/lua-language-server 3.19.2 ==="
if (-not (Test-Path "$buildDir\luals")) {
  git clone --depth 1 --branch 3.19.2 --recurse-submodules --shallow-submodules https://github.com/LuaLS/lua-language-server.git "$buildDir\luals"
}

Write-Host "=== ALL SOURCES FETCHED ==="
