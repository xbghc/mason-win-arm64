#!/usr/bin/env python3
"""Check upstream GitHub releases, update versions.json, and reuse unchanged release artifacts."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import re
import shutil
import urllib.error
import urllib.request
from pathlib import Path

WIN_ARM64_ASSET_RE = re.compile(
    r"((win|windows).*(arm64|aarch64)|(arm64|aarch64).*(win|windows))",
    re.IGNORECASE,
)


def gh_headers() -> dict[str, str]:
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "mason-win-arm64-sync",
    }
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return headers


def gh_get_json(url: str) -> dict | list | None:
    req = urllib.request.Request(url, headers=gh_headers())
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise


def download_file(url: str, dest: Path, expected_sha256: str | None = None) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": "mason-win-arm64-sync"})
    h = hashlib.sha256()
    tmp = dest.with_suffix(dest.suffix + ".part")
    with urllib.request.urlopen(req, timeout=120) as resp, tmp.open("wb") as out:
        while True:
            chunk = resp.read(256 * 1024)
            if not chunk:
                break
            out.write(chunk)
            h.update(chunk)
    actual = h.hexdigest()
    if expected_sha256 and actual.lower() != expected_sha256.lower():
        tmp.unlink(missing_ok=True)
        raise RuntimeError(
            f"SHA256 mismatch for {dest.name}: expected {expected_sha256}, got {actual}"
        )
    tmp.replace(dest)


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def parse_checksums(text: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for line in text.splitlines():
        parts = line.strip().split()
        if len(parts) >= 2:
            result[parts[-1]] = parts[0]
    return result


def pick_unique_tag(registry_repo: str, preferred_date: str | None = None) -> str:
    base = preferred_date or dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d")
    tags_data = gh_get_json(f"https://api.github.com/repos/{registry_repo}/tags?per_page=100")
    existing = {t["name"] for t in (tags_data or []) if isinstance(t, dict) and "name" in t}
    if base not in existing:
        return base
    idx = 2
    while f"{base}.{idx}" in existing:
        idx += 1
    return f"{base}.{idx}"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default="xbghc/mason-win-arm64", help="Target Mason registry GitHub repo")
    parser.add_argument("--root", default=str(Path(__file__).resolve().parent.parent))
    parser.add_argument("--check-only", action="store_true", help="Do not modify versions.json or download files")
    parser.add_argument("--download-reusable", action="store_true", help="Download unchanged zips from latest release into dist/")
    parser.add_argument("--force-rebuild", action="store_true", help="Mark all packages for rebuild regardless of existing release assets")
    parser.add_argument("--respect-local-toolchains", action="store_true", help="Skip optional packages whose required compiler (e.g. dotnet) is missing locally")
    args = parser.parse_args()

    root = Path(args.root)
    versions_path = root / "versions.json"
    dist_dir = root / "dist"
    versions: dict[str, dict] = json.loads(versions_path.read_text(encoding="utf-8"))

    # 1. Inspect existing registry latest release on GitHub
    latest_reg_release = gh_get_json(f"https://api.github.com/repos/{args.repo}/releases/latest")
    remote_assets: dict[str, str] = {}
    remote_checksums: dict[str, str] = {}
    prev_release_tag = None

    if isinstance(latest_reg_release, dict):
        prev_release_tag = latest_reg_release.get("tag_name")
        for asset in latest_reg_release.get("assets", []):
            name = asset.get("name")
            url = asset.get("browser_download_url")
            if name and url:
                remote_assets[name] = url
        if "checksums.txt" in remote_assets:
            req = urllib.request.Request(remote_assets["checksums.txt"], headers={"User-Agent": "mason-win-arm64-sync"})
            with urllib.request.urlopen(req, timeout=30) as resp:
                remote_checksums = parse_checksums(resp.read().decode("utf-8"))

    updated_versions: list[tuple[str, str, str]] = []
    needs_build: list[str] = []
    reused_packages: list[str] = []
    skipped_packages: list[str] = []
    upstream_arm64_notices: list[str] = []
    status_rows: list[tuple[str, str, str, str]] = []

    # 2. Check each package against upstream GitHub Releases
    for pkg, cfg in versions.items():
        upstream_repo = cfg["repo"]
        old_ver = cfg["version"]
        rel = gh_get_json(f"https://api.github.com/repos/{upstream_repo}/releases/latest")
        if not isinstance(rel, dict) or not rel.get("tag_name"):
            raise RuntimeError(f"Failed to query latest release for {upstream_repo}")

        latest_ver = rel["tag_name"]
        arm64_assets = [
            a["name"]
            for a in rel.get("assets", [])
            if isinstance(a.get("name"), str) and WIN_ARM64_ASSET_RE.search(a["name"])
        ]
        if arm64_assets:
            notice = f"{pkg} ({upstream_repo}@{latest_ver}) now ships upstream win-arm64 assets: {', '.join(arm64_assets)}"
            upstream_arm64_notices.append(notice)
            print(f"[NOTICE] {notice}")

        if latest_ver != old_ver:
            updated_versions.append((pkg, old_ver, latest_ver))
            cfg["version"] = latest_ver
            print(f"[UPDATE] {pkg}: {old_ver} -> {latest_ver}")
        else:
            print(f"[OK]     {pkg}: up to date ({latest_ver})")

        req_tool = cfg.get("requires")
        if args.respect_local_toolchains and req_tool and shutil.which(req_tool) is None:
            artifact_name = cfg["artifact"].format(version=latest_ver)
            if artifact_name in remote_assets and not args.force_rebuild:
                reused_packages.append(pkg)
                status_rows.append((pkg, old_ver, latest_ver, "reuse remote (missing local toolchain)"))
                if args.download_reusable and not args.check_only:
                    dest = dist_dir / artifact_name
                    if not dest.is_file():
                        print(f"[REUSE]  Downloading {artifact_name} from release {prev_release_tag}...")
                        download_file(remote_assets[artifact_name], dest, remote_checksums.get(artifact_name))
            else:
                skipped_packages.append(pkg)
                status_rows.append((pkg, old_ver, latest_ver, f"skipped ({req_tool} not installed)"))
            continue

        artifact_name = cfg["artifact"].format(version=latest_ver)
        local_artifact = dist_dir / artifact_name

        if args.force_rebuild:
            if not args.check_only and local_artifact.is_file():
                local_artifact.unlink()
            needs_build.append(pkg)
            status_rows.append((pkg, old_ver, latest_ver, "rebuild (forced)"))
        elif artifact_name in remote_assets:
            reused_packages.append(pkg)
            status_rows.append((pkg, old_ver, latest_ver, f"reuse ({prev_release_tag})"))
            if args.download_reusable and not args.check_only:
                need_dl = True
                if local_artifact.is_file():
                    expected = remote_checksums.get(artifact_name)
                    if not expected or sha256_file(local_artifact).lower() == expected.lower():
                        need_dl = False
                if need_dl:
                    print(f"[REUSE]  Downloading {artifact_name} from release {prev_release_tag}...")
                    download_file(remote_assets[artifact_name], local_artifact, remote_checksums.get(artifact_name))
        else:
            needs_build.append(pkg)
            reason = "version bump" if latest_ver != old_ver else "missing from latest release"
            status_rows.append((pkg, old_ver, latest_ver, f"build ({reason})"))

    # 3. Write updated versions.json if changed and prune stale zips in dist/
    if updated_versions and not args.check_only:
        versions_path.write_text(
            json.dumps(versions, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
            newline="\n",
        )
        print(f"Updated {versions_path}")

    if not args.check_only and dist_dir.is_dir():
        expected_zips = {
            cfg["artifact"].format(version=cfg["version"])
            for cfg in versions.values()
        }
        for existing_zip in dist_dir.glob("*.zip"):
            if existing_zip.name != "registry.json.zip" and existing_zip.name not in expected_zips:
                print(f"[CLEAN]  Removing outdated artifact {existing_zip.name}")
                existing_zip.unlink()

    needs_publish = bool(needs_build)
    release_tag = pick_unique_tag(args.repo) if needs_publish else (prev_release_tag or "")

    # 4. Prepare release notes draft in dist/release-notes.md when publishing
    if needs_publish and not args.check_only:
        dist_dir.mkdir(parents=True, exist_ok=True)
        lines = [
            "## Native Windows ARM64 (`win_arm64`) Mason Packages",
            "",
            "| Package | Previous | Current | Action |",
            "| :--- | :--- | :--- | :--- |",
        ]
        for pkg, old_v, new_v, action in status_rows:
            lines.append(f"| `{pkg}` | `{old_v}` | `{new_v}` | {action} |")
        if upstream_arm64_notices:
            lines.extend(["", "### Upstream Native ARM64 Availability Notices", ""])
            for n in upstream_arm64_notices:
                lines.append(f"- {n}")
        (dist_dir / "release-notes.md").write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")

    # 5. Export GitHub Actions outputs & summary if running in CI
    gh_output = os.environ.get("GITHUB_OUTPUT")
    if gh_output:
        with open(gh_output, "a", encoding="utf-8") as f:
            f.write(f"needs_publish={'true' if needs_publish else 'false'}\n")
            f.write(f"needs_build={','.join(needs_build)}\n")
            f.write(f"release_tag={release_tag}\n")
            updates_str = ", ".join(f"{p} {o}->{n}" for p, o, n in updated_versions)
            f.write(f"updated_summary={updates_str}\n")

    gh_summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if gh_summary:
        with open(gh_summary, "a", encoding="utf-8") as f:
            f.write("### Mason `win_arm64` Upstream Sync Summary\n\n")
            f.write("| Package | Previous | Upstream Latest | Status |\n")
            f.write("| :--- | :--- | :--- | :--- |\n")
            for pkg, old_v, new_v, action in status_rows:
                f.write(f"| `{pkg}` | `{old_v}` | `{new_v}` | {action} |\n")
            if upstream_arm64_notices:
                f.write("\n> [!TIP]\n")
                for n in upstream_arm64_notices:
                    f.write(f"> - {n}\n")

    print(
        f"\nSummary: needs_publish={needs_publish}, needs_build={needs_build}, "
        f"reused={reused_packages}, release_tag={release_tag or '(none)'}"
    )


if __name__ == "__main__":
    main()
