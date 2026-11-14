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


def make_download_entry(cfg: dict, base_url: str) -> tuple[str, dict]:
    ver = cfg["version"]
    arm64_zip = cfg["artifact"].format(version=ver)
    x64_file = cfg["win_x64_file"].format(version=ver)
    x64_url = cfg["win_x64_url"].format(version=ver)
    return arm64_zip, {
        "id": f"{cfg['purl_prefix']}@{ver}",
        "download": [
            {
                "target": "win_arm64",
                "files": {
                    arm64_zip: f"{base_url}/{arm64_zip}",
                },
            },
            {
                "target": "win_x64",
                "files": {
                    x64_file: x64_url,
                },
            },
        ],
    }


def build_specs(repo: str, tag: str, dist_dir: Path, versions: dict[str, dict]) -> list[dict]:
    base_url = f"https://github.com/{repo}/releases/download/{tag}"
    specs: list[dict] = []

    # 1. stylua
    if "stylua" in versions:
        stylua_zip, stylua_src = make_download_entry(versions["stylua"], base_url)
        if (dist_dir / stylua_zip).is_file():
            specs.append({
                "schema": "registry+v1",
                "name": "stylua",
                "description": "An opinionated Lua code formatter (native Windows ARM64 build).",
                "homepage": "https://github.com/JohnnyMorganz/StyLua",
                "licenses": ["MPL-2.0"],
                "languages": ["Lua", "Luau"],
                "categories": ["Formatter", "LSP"],
                "source": stylua_src,
                "bin": {
                    "stylua": "stylua.exe",
                },
                "neovim": {
                    "lspconfig": "stylua",
                },
            })

    # 2. shfmt
    if "shfmt" in versions:
        shfmt_zip, shfmt_src = make_download_entry(versions["shfmt"], base_url)
        if (dist_dir / shfmt_zip).is_file():
            specs.append({
                "schema": "registry+v1",
                "name": "shfmt",
                "description": "A shell formatter (sh/bash/zsh/mksh) (native Windows ARM64 build).",
                "homepage": "https://github.com/mvdan/sh",
                "licenses": ["BSD-3-Clause"],
                "languages": ["Bash", "Mksh", "Shell", "Zsh"],
                "categories": ["Formatter"],
                "source": shfmt_src,
                "bin": {
                    "shfmt": "shfmt.exe",
                },
            })

    # 3. lua-language-server
    if "lua-language-server" in versions:
        luals_zip, luals_src = make_download_entry(versions["lua-language-server"], base_url)
        if (dist_dir / luals_zip).is_file():
            specs.append({
                "schema": "registry+v1",
                "name": "lua-language-server",
                "description": "A language server that offers Lua language support (native Windows ARM64 build).",
                "homepage": "https://github.com/LuaLS/lua-language-server",
                "licenses": ["MIT"],
                "languages": ["Lua"],
                "categories": ["LSP"],
                "source": luals_src,
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

    # 4. marksman
    if "marksman" in versions:
        marksman_zip, marksman_src = make_download_entry(versions["marksman"], base_url)
        if (dist_dir / marksman_zip).is_file():
            specs.append({
                "schema": "registry+v1",
                "name": "marksman",
                "description": "Markdown LSP server providing completion, cross-references, diagnostics, and more (native Windows ARM64 build).",
                "homepage": "https://github.com/artempyanykh/marksman",
                "licenses": ["MIT"],
                "languages": ["Markdown"],
                "categories": ["LSP"],
                "source": marksman_src,
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
    versions: dict[str, dict] = json.loads((root / "versions.json").read_text(encoding="utf-8"))
    dist_dir.mkdir(parents=True, exist_ok=True)
    pkgs_dir.mkdir(parents=True, exist_ok=True)

    specs = build_specs(args.repo, args.tag, dist_dir, versions)
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

    expected_zips = {
        cfg["artifact"].format(version=cfg["version"])
        for cfg in versions.values()
    }
    checksum_lines: list[str] = []
    for artifact in sorted(dist_dir.iterdir(), key=lambda p: p.name):
        if artifact.is_file() and (
            artifact.name in expected_zips
            or artifact.name in {"registry.json", "registry.json.zip"}
        ):
            checksum_lines.append(f"{sha256_file(artifact)}  {artifact.name}")

    with (dist_dir / "checksums.txt").open("w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(checksum_lines) + "\n")

    print(f"Generated registry with {len(specs)} packages: {[s['name'] for s in specs]}")


if __name__ == "__main__":
    main()
