#!/usr/bin/env python3
"""Generate Mason custom registry (registry.json.zip + checksums.txt) for Windows ARM64."""

from __future__ import annotations

import argparse
import hashlib
import json
import zipfile
from pathlib import Path


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def build_specs(repo: str, tag: str, dist_dir: Path) -> list[dict]:
    base_url = f"https://github.com/{repo}/releases/download/{tag}"
    specs: list[dict] = []

    # 1. stylua (v2.6.0)
    stylua_zip = "stylua-v2.6.0-win-arm64.zip"
    if (dist_dir / stylua_zip).is_file():
        specs.append({
            "schema": "registry+v1",
            "name": "stylua",
            "description": "An opinionated Lua code formatter (native Windows ARM64 build).",
            "homepage": "https://github.com/JohnnyMorganz/StyLua",
            "licenses": ["MPL-2.0"],
            "languages": ["Lua", "Luau"],
            "categories": ["Formatter", "LSP"],
            "source": {
                "id": "pkg:generic/johnnymorganz/stylua@v2.6.0",
                "download": [
                    {
                        "target": "win_arm64",
                        "files": {
                            stylua_zip: f"{base_url}/{stylua_zip}",
                        },
                    },
                    {
                        "target": "win_x64",
                        "files": {
                            "stylua-windows-x86_64.zip": "https://github.com/JohnnyMorganz/StyLua/releases/download/v2.6.0/stylua-windows-x86_64.zip",
                        },
                    },
                ],
            },
            "bin": {
                "stylua": "stylua.exe",
            },
            "neovim": {
                "lspconfig": "stylua",
            },
        })

    # 2. shfmt (v3.14.1)
    shfmt_zip = "shfmt-v3.14.1-win-arm64.zip"
    if (dist_dir / shfmt_zip).is_file():
        specs.append({
            "schema": "registry+v1",
            "name": "shfmt",
            "description": "A shell formatter (sh/bash/zsh/mksh) (native Windows ARM64 build).",
            "homepage": "https://github.com/mvdan/sh",
            "licenses": ["BSD-3-Clause"],
            "languages": ["Bash", "Mksh", "Shell", "Zsh"],
            "categories": ["Formatter"],
            "source": {
                "id": "pkg:generic/mvdan/sh@v3.14.1",
                "download": [
                    {
                        "target": "win_arm64",
                        "files": {
                            shfmt_zip: f"{base_url}/{shfmt_zip}",
                        },
                    },
                    {
                        "target": "win_x64",
                        "files": {
                            "shfmt.exe": "https://github.com/mvdan/sh/releases/download/v3.14.1/shfmt_v3.14.1_windows_amd64.exe",
                        },
                    },
                ],
            },
            "bin": {
                "shfmt": "shfmt.exe",
            },
        })

    # 3. lua-language-server (3.19.2)
    luals_zip = "lua-language-server-3.19.2-win32-arm64.zip"
    if (dist_dir / luals_zip).is_file():
        specs.append({
            "schema": "registry+v1",
            "name": "lua-language-server",
            "description": "A language server that offers Lua language support (native Windows ARM64 build).",
            "homepage": "https://github.com/LuaLS/lua-language-server",
            "licenses": ["MIT"],
            "languages": ["Lua"],
            "categories": ["LSP"],
            "source": {
                "id": "pkg:generic/LuaLS/lua-language-server@3.19.2",
                "download": [
                    {
                        "target": "win_arm64",
                        "files": {
                            luals_zip: f"{base_url}/{luals_zip}",
                        },
                    },
                    {
                        "target": "win_x64",
                        "files": {
                            "lua-language-server-3.19.2-win32-x64.zip": "https://github.com/LuaLS/lua-language-server/releases/download/3.19.2/lua-language-server-3.19.2-win32-x64.zip",
                        },
                    },
                ],
            },
            "schemas": {
                "lsp": "vscode:https://raw.githubusercontent.com/LuaLS/vscode-lua/master/package.json",
            },
            "bin": {
                "lua-language-server": "bin/lua-language-server.exe",
            },
            "neovim": {
                "lspconfig": "lua_ls",
            },
        })

    # 4. marksman (2026-02-08)
    marksman_zip = "marksman-2026-02-08-win-arm64.zip"
    if (dist_dir / marksman_zip).is_file():
        specs.append({
            "schema": "registry+v1",
            "name": "marksman",
            "description": "Markdown LSP server providing completion, cross-references, diagnostics, and more (native Windows ARM64 build).",
            "homepage": "https://github.com/artempyanykh/marksman",
            "licenses": ["MIT"],
            "languages": ["Markdown"],
            "categories": ["LSP"],
            "source": {
                "id": "pkg:generic/artempyanykh/marksman@2026-02-08",
                "download": [
                    {
                        "target": "win_arm64",
                        "files": {
                            marksman_zip: f"{base_url}/{marksman_zip}",
                        },
                    },
                    {
                        "target": "win_x64",
                        "files": {
                            "marksman.exe": "https://github.com/artempyanykh/marksman/releases/download/2026-02-08/marksman.exe",
                        },
                    },
                ],
            },
            "bin": {
                "marksman": "marksman.exe",
            },
            "neovim": {
                "lspconfig": "marksman",
            },
        })

    return specs


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", default="xbghc/mason-win-arm64")
    parser.add_argument("--tag", default="2026-11-14")
    parser.add_argument("--root", default=str(Path(__file__).resolve().parent.parent))
    args = parser.parse_args()

    root = Path(args.root)
    dist_dir = root / "dist"
    pkgs_dir = root / "packages"
    dist_dir.mkdir(parents=True, exist_ok=True)
    pkgs_dir.mkdir(parents=True, exist_ok=True)

    specs = build_specs(args.repo, args.tag, dist_dir)
    if not specs:
        raise SystemExit("No built artifacts found in dist/!")

    for spec in specs:
        pkg_dir = pkgs_dir / spec["name"]
        pkg_dir.mkdir(parents=True, exist_ok=True)
        with (pkg_dir / "package.json").open("w", encoding="utf-8", newline="\n") as f:
            json.dump(spec, f, indent=2, ensure_ascii=False)
            f.write("\n")

    reg_json_path = dist_dir / "registry.json"
    reg_bytes = (json.dumps(specs, separators=(",", ":"), ensure_ascii=False) + "\n").encode("utf-8")
    reg_json_path.write_bytes(reg_bytes)

    reg_zip_path = dist_dir / "registry.json.zip"
    with zipfile.ZipFile(reg_zip_path, mode="w", compression=zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("registry.json", reg_bytes)

    checksum_lines: list[str] = []
    for artifact in sorted(dist_dir.iterdir(), key=lambda p: p.name):
        if artifact.is_file() and artifact.name != "checksums.txt":
            checksum_lines.append(f"{sha256_file(artifact)}  {artifact.name}")

    with (dist_dir / "checksums.txt").open("w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(checksum_lines) + "\n")

    print(f"Generated registry with {len(specs)} packages: {[s['name'] for s in specs]}")


if __name__ == "__main__":
    main()
