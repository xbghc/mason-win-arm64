# mason-win-arm64

面向 **Windows 11 on ARM64 (`win_arm64` / `aarch64-pc-windows-msvc`)** 的自定义 [`mason.nvim`](https://github.com/mason-org/mason.nvim) 软件源与本地原生编译脚本。

许多 Neovim / LazyVim 常用工具（如 `stylua`、`shfmt`、`lua-language-server`、`marksman`）在官方 `mason-org/mason-registry` 中仅声明了 `win_x64` 目标，导致在原生 ARM64 版 Neovim 下启动报错：

```text
Installation failed for Package(name=...) error="The current platform is unsupported."
```

本仓库提供两层解决方案：
1. **原生 `win_arm64` 编译与 Mason 自定义源**：从上游源码原生编译 `ARM64`（PE Machine `0xAA64`）可执行文件并发布为标准 Mason Registry（`registry.json.zip` + `checksums.txt`）。
2. **`win_x64` 自动回退**：对于暂未原生编译或未来新增的无 `win_arm64` 包（如依赖 `.NET SDK` 的 `marksman`），在 Neovim 配置中自动回退到 `win_x64`（借助 Windows 11 Prism 转译运行）。

## 已收录原生 `win_arm64` 包

| 包名 | 版本 | 上游仓库 | 编译工具链 |
| :--- | :--- | :--- | :--- |
| `stylua` | `v2.6.0` | `JohnnyMorganz/StyLua` | Rust (`aarch64-pc-windows-msvc`, 全语法特性 `lua52/53/54/luajit/luau`) |
| `shfmt` | `v3.14.1` | `mvdan/sh` | Go (`windows/arm64`) |
| `lua-language-server` | `3.19.2` | `LuaLS/lua-language-server` | MSVC ARM64 (`cl.exe` + `luamake` + `ninja`) |

> 如本机安装了 `.NET SDK`，也可运行 `scripts/build-marksman.ps1` 编译原生 `win_arm64` 版 `marksman` 并重新执行 `scripts/pack-registry.py` 加入软件源。

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

保存后在 Neovim 中执行 `:MasonUpdate`，即可自动从本仓库拉取原生 `win_arm64` 包，并对其他缺失 `win_arm64` 的包平滑回退到 `win_x64`。

## 本地复现构建与发布

```powershell
# 1. 拉取上游源码与依赖
pwsh -NoProfile -File scripts/fetch-sources.ps1

# 2. 编译原生 ARM64 二进制并校验 PE 0xAA64 头
pwsh -NoProfile -File scripts/build-all-native.ps1

# 3. 生成 packages/*/package.json、dist/registry.json.zip 与 dist/checksums.txt
python scripts/pack-registry.py --repo xbghc/mason-win-arm64 --tag 2026-11-14

# 4. 发布到 GitHub Release
gh release create 2026-11-14 dist/*.zip dist/checksums.txt --title "2026-11-14" --notes "Native Windows ARM64 Mason packages"
```
