#!/usr/bin/env python3
"""Version-gated, reversible compatibility workaround for Hermes CN 0.20.0-cn.5.

The script is deliberately conservative: it validates the target version and
YAML before mutation, creates a timestamped backup, writes the configuration
atomically, verifies the result, and rolls back both config and plugin files
if any post-write step fails.
"""
from __future__ import annotations

import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone

import yaml

TARGET_VERSION = "0.20.0-cn.5"
PLUGIN_NAME = "gateway-cron-name-fix"


def _hermes_home() -> Path:
    default = Path(os.environ.get("HERMES_HOME", str(Path.home() / ".hermes")))
    positional = [a for a in sys.argv[1:] if not a.startswith("--")]
    hh = Path(positional[0]) if positional else default
    if not hh.is_dir():
        raise SystemExit(f"HERMES_HOME not found: {hh}")
    return hh


def _detect_hermes_version(hh: Path) -> str | None:
    versions_dirs = [hh / "data" / "versions", hh.parent / "versions"]
    for versions_dir in versions_dirs:
        if not versions_dir.is_dir():
            continue
        candidates = sorted(
            (p for p in versions_dir.iterdir() if p.is_dir()),
            key=lambda p: p.stat().st_mtime,
            reverse=True,
        )
        for candidate in candidates:
            exe = candidate / "hermes-agent-cn-runtime-win32-x64.exe"
            if not exe.is_file():
                continue
            try:
                result = subprocess.run(
                    [str(exe), "--version"], capture_output=True, text=True, timeout=15
                )
                text = (result.stdout or "") + (result.stderr or "")
                m = re.search(r"(\d+\.\d+\.\d+-cn\.\d+)", text)
                if m:
                    return m.group(1)
            except (OSError, subprocess.SubprocessError):
                pass
            if re.fullmatch(r"\d+\.\d+\.\d+-cn\.\d+", candidate.name):
                return candidate.name
    return None


def _version_guard(hh: Path) -> None:
    detected = _detect_hermes_version(hh)
    if detected != TARGET_VERSION:
        raise SystemExit(
            f"ERROR: This workaround targets Hermes CN Desktop {TARGET_VERSION} only.\n"
            f"Detected version: {detected or 'unknown'}\n"
            "Refusing to modify configuration."
        )


def _build_config(original: str) -> str:
    data = yaml.safe_load(original)
    if not isinstance(data, dict):
        raise ValueError("config.yaml root must be a YAML mapping")
    plugins = data.get("plugins")
    if not isinstance(plugins, dict):
        raise ValueError("config.yaml is missing the plugins mapping")
    enabled = plugins.get("enabled")
    if not isinstance(enabled, list):
        raise ValueError("config.yaml is missing plugins.enabled list")
    if PLUGIN_NAME not in enabled:
        enabled.append(PLUGIN_NAME)
    new_text = yaml.safe_dump(data, allow_unicode=True, sort_keys=False)
    validated = yaml.safe_load(new_text)
    if PLUGIN_NAME not in validated.get("plugins", {}).get("enabled", []):
        raise ValueError("generated config did not retain plugin enablement")
    return new_text


def _atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", newline="", dir=path.parent, delete=False) as tmp:
        tmp.write(text)
        tmp_path = Path(tmp.name)
    try:
        os.replace(tmp_path, path)
    finally:
        if tmp_path.exists():
            tmp_path.unlink()


def _plugin_files(plugin_dir: Path) -> dict[Path, str | None]:
    return {
        plugin_dir / "plugin.yaml": None,
        plugin_dir / "__init__.py": None,
    }


def _write_plugin(plugin_dir: Path) -> None:
    plugin_dir.mkdir(parents=True, exist_ok=True)
    (plugin_dir / "plugin.yaml").write_text(
        "name: gateway-cron-name-fix\n"
        "kind: standalone\n"
        "version: 1.0.0\n"
        "description: \"Local workaround for 0.20.0-cn.5 gateway crash: "
        "NameError InProcessCronScheduler is not defined\"\n"
        "author: local-fix\n",
        encoding="utf-8",
    )
    (plugin_dir / "__init__.py").write_text(
        '"""Local workaround for Hermes CN 0.20.0-cn.5 gateway crash loop."""\n\n'
        "def register(ctx) -> None:  # noqa: ARG001\n"
        "    try:\n"
        "        import gateway.run as _gateway_run\n"
        "        from cron.scheduler_provider import InProcessCronScheduler as _in_process\n"
        "        _gateway_run.InProcessCronScheduler = _in_process\n"
        "    except Exception:\n"
        "        pass\n",
        encoding="utf-8",
    )


def _verify(cfg_path: Path, plugin_dir: Path) -> None:
    errors: list[str] = []
    if not (plugin_dir / "plugin.yaml").is_file():
        errors.append(f"Missing {plugin_dir / 'plugin.yaml'}")
    if not (plugin_dir / "__init__.py").is_file():
        errors.append(f"Missing {plugin_dir / '__init__.py'}")
    try:
        cfg = yaml.safe_load(cfg_path.read_text(encoding="utf-8"))
        if PLUGIN_NAME not in cfg.get("plugins", {}).get("enabled", []):
            errors.append("Plugin not in plugins.enabled list")
    except Exception as exc:
        errors.append(f"config.yaml YAML verify failed: {exc}")
    if errors:
        raise RuntimeError("Verification failed:\n" + "\n".join(f"  - {e}" for e in errors))


def _backup(path: Path) -> Path:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    backup = path.with_name(path.name + f".hermes-cron-fix.{stamp}.bak")
    shutil.copy2(path, backup)
    return backup


def main() -> None:
    dry_run = "--dry-run" in sys.argv
    hermes_home = _hermes_home()
    _version_guard(hermes_home)

    cfg_path = hermes_home / "config.yaml"
    plugin_dir = hermes_home / "plugins" / PLUGIN_NAME
    if not cfg_path.exists():
        raise SystemExit(f"config.yaml missing: {cfg_path}")

    original = cfg_path.read_text(encoding="utf-8")
    new_text = _build_config(original)
    already_enabled = PLUGIN_NAME in (yaml.safe_load(original).get("plugins", {}).get("enabled", []) or [])

    if dry_run:
        print("DRY-RUN: no files will be modified.")
        print(f"Hermes home: {hermes_home}")
        print(f"Target version: {TARGET_VERSION}")
        print(f"Plugin directory: {plugin_dir}")
        print(f"Plugin already enabled: {already_enabled}")
        return

    existed_before = plugin_dir.exists()
    snapshots: dict[Path, bytes | None] = {}
    for path in _plugin_files(plugin_dir):
        snapshots[path] = path.read_bytes() if path.exists() else None

    backup_path = _backup(cfg_path)
    try:
        _atomic_write(cfg_path, new_text)
        _write_plugin(plugin_dir)
        _verify(cfg_path, plugin_dir)
    except Exception as exc:
        try:
            shutil.copy2(backup_path, cfg_path)
            for path, content in snapshots.items():
                if content is None:
                    if path.exists():
                        path.unlink()
                else:
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_bytes(content)
            if not existed_before and plugin_dir.exists() and not any(plugin_dir.iterdir()):
                plugin_dir.rmdir()
        except Exception as rollback_exc:
            raise SystemExit(f"Repair failed: {exc}\nROLLBACK ALSO FAILED: {rollback_exc}") from exc
        raise SystemExit(f"Repair failed; changes were rolled back. Backup: {backup_path}\n{exc}") from exc

    print("OK: plugin enabled and verified.")
    print(f"Backup: {backup_path}")
    print(f"Plugin: {plugin_dir}")
    print(f"Config: {cfg_path}")


if __name__ == "__main__":
    main()
