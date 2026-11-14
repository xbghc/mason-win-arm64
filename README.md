# mason-win-arm64

面向 **Windows 11 on ARM64 (`win_arm64` / `aarch64-pc-windows-msvc`)** 的自定义 [`mason.nvim`](https://github.com/mason-org/mason.nvim) 软件源、原生编译脚本与上游自动同步工作流。

许多 Neovim / LazyVim 常用工具（如 `stylua`、`shfmt`、`lua-language-server`、`marksman`）在官方 `mason-org/mason-registry` 中仅声明了 `win_x64` 目标，导致在原生 ARM64 版 Neovim 下启动报错：

```text
Installation failed for Package(name=...) error="The current platform is unsupported."
```

本仓库提供两层解决方案：
1. **原生 `win_arm64` 编译与自动追更 Mason 源**：基于 [`versions.json`](versions.json) 追踪上游 GitHub Releases，在原生 `windows-11-arm` 环境下自动编译 `ARM64`（PE Machine `0xAA64`）可执行文件并发布为标准 Mason Registry（`registry.json.zip` + `checksums.txt`）。
2. **`win_x64` 自动回退**：对于暂未收录或未来新增的无 `win_arm64` 包，在 Neovim 配置中自动回退到 `win_x64`（借助 Windows 11 Prism 转译运行）。

## 收录包清单（由 `versions.json` 驱动）

| 包名 | 上游仓库 | 编译工具链 | 备注 |
| :--- | :--- | :--- | :--- |
| `stylua` | `JohnnyMorganz/StyLua` | Rust (`aarch64-pc-windows-msvc`, 全语法特性 `lua52/53/54/luajit/luau`) | 本地 / CI 构建 |
| `shfmt` | `mvdan/sh` | Go (`windows/arm64`) | 本地 / CI 构建 |
| `lua-language-server` | `LuaLS/lua-language-server` | MSVC ARM64 (`cl.exe` + `luamake` + `ninja`) | 本地 / CI 构建 |
| `marksman` | `artempyanykh/marksman` | .NET SDK (`dotnet publish -r win-arm64`) | CI 默认构建；本地检测到 `dotnet` 时自动构建 |

## 在 LazyVim / `mason.nvim` 中使用

新建 `~/.config/nvim/lua/plugins/mason.lua`（Windows 默认路径 `~/AppData/Local/nvim/lua/plugins/mason.lua`）：

```lua
return {
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      opts.registries = {
        "github:xbghc/mason-win-arm64",
        "github:mason-org/mason-registry",
      }

      -- 当某个包没有提供 win_arm64 构建时，自动回退安装 win_x64 版本（通过 Windows 11 Prism 运行）
      local ok_plat, platform = pcall(require, "mason-core.platform")
      if ok_plat and platform.is.win_arm64 then
        local util = require("mason-core.installer.compiler.util")
        if not util._win_arm64_fallback_patched then
          util._win_arm64_fallback_patched = true

          local orig_coalesce = util.coalesce_by_target
          util.coalesce_by_target = function(candidates, install_opts)
            local res = orig_coalesce(candidates, install_opts)
            if res:is_failure() and not (install_opts and install_opts.target) then
              return orig_coalesce(
                candidates,
                vim.tbl_extend("force", install_opts or {}, { target = "win_x64" })
              )
            end
            return res
          end

          local orig_ensure = util.ensure_valid_platform
          util.ensure_valid_platform = function(platforms)
            local res = orig_ensure(platforms)
            if res:is_failure() and vim.tbl_contains(platforms, "win_x64") then
              return require("mason-core.result").success()
            end
            return res
          end
        end
      end
    end,
  },
}
```

保存后在 Neovim 中执行 `:MasonUpdate`，即可自动从本仓库拉取最新原生 `win_arm64` 包，并对其他缺失 `win_arm64` 的包平滑回退到 `win_x64`。

## 自动跟随远端版本更新

### 1. 云端全自动追更（GitHub Actions `windows-11-arm`）

仓库内置了 [`.github/workflows/update-registry.yml`](.github/workflows/update-registry.yml)：
- **每日定时巡检**（每天北京时间 `10:00`，也支持在 GitHub Actions 页面手动点击 `Run workflow` 触发）；
- `scripts/sync-upstream.py` 自动查询各上游仓库最新 Release：
  - 若无任何版本变更且最新 Release 产物齐全，15 秒内直接跳过退出；
  - 若某几个包发布了新版本（或首次补齐 `marksman`），**未变动的包会直接从本仓库上一次 Release 下载复用并校验 SHA256**，仅按需安装对应工具链增量编译变动包；
  - 若检测到上游官方已开始发布 `win-arm64` / `aarch64` 原生包，自动在 Action Summary 与 Release Notes 中输出提醒；
- 编译完成后自动更新 `versions.json`、`packages/*/package.json` 并发布新 GitHub Release，客户端只需在 Neovim 中运行 `:MasonUpdate` 即可升级。

### 2. 本地一键检查与增量构建

```powershell
# 仅检查远端是否有新版本（不修改文件、不编译）
pwsh -NoProfile -File scripts/update-local.ps1 -CheckOnly

# 同步远端最新版本、复用未变动产物、增量编译变动包并打包 dist/
pwsh -NoProfile -File scripts/update-local.ps1

# 同步、增量编译并直接调用 gh 发布到 GitHub Release
pwsh -NoProfile -File scripts/update-local.ps1 -Publish
```

### 3. 手动分步复现构建

```powershell
# 1. 根据 versions.json 拉取上游源码与依赖
pwsh -NoProfile -File scripts/fetch-sources.ps1

# 2. 编译原生 ARM64 二进制并校验 PE 0xAA64 头
pwsh -NoProfile -File scripts/build-all-native.ps1

# 3. 生成 packages/*/package.json、dist/registry.json.zip 与 dist/checksums.txt
python scripts/pack-registry.py --repo xbghc/mason-win-arm64 --tag 2026-11-14
```
