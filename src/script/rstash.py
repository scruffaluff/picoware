#!/usr/bin/env -S uv run --script
# /// script
# dependencies = [
#   "loguru~=0.7.0",
#   "typer~=0.15.0",
# ]
# requires-python = "~=3.12"
# ///

"""Backup files with Rclone."""

import atexit
import json
import os
from pathlib import Path
import re
from re import Pattern
import subprocess
import sys
import platform
import tempfile
from typing import Annotated, Any, Iterable

from loguru import logger
import typer
from typer import Option, Typer


__version__ = "0.0.1"


cli = Typer(
    add_completion=False,
    help="Backup files with Rclone.",
    no_args_is_help=True,
    pretty_exceptions_enable=False,
)


state: dict[str, Any] = {"config": None, "dry": False, "links": []}


def clean_paths() -> None:
    """Remove temporary symlinks."""
    for link in state["links"]:
        link.unlink(missing_ok=True)


def create_manifest(files: Iterable[Path]) -> Path:
    """Create manifest for files sync."""
    file, manifest_ = tempfile.mkstemp(suffix=".txt")
    manifest = Path(manifest_).absolute()
    os.close(file)
    manifest.write_text("\n".join(map(str, files)) + "\n")
    return manifest


def find_files(config: dict[str, Any], source: Path) -> list[Path]:
    """Find all files specified for syncing."""
    files = []
    root_excludes = [re.compile(exclude) for exclude in config.get("excludes", [])]
    root_includes = [re.compile(include) for include in config.get("includes", [])]

    for path in config["paths"]:
        if isinstance(path, dict):
            alternates = [
                source / alternate for alternate in path.get("alternates", [])
            ]
            excludes = root_excludes + [
                re.compile(exclude) for exclude in path.get("excludes", [])
            ]
            includes = root_excludes + [
                re.compile(include) for include in path.get("includes", [])
            ]
            path = source / path["path"]
        else:
            alternates = []
            excludes = root_excludes
            includes = root_includes
            path = source / path

        includes = includes or [re.compile("^.*$")]
        if not path.exists():
            for alternate in alternates:
                if alternate.exists():
                    path.symlink_to(alternate)
                    state["links"].append(path)
                    break
            else:
                continue

        for file in path.iterdir():
            if match_filename(includes, file) and not match_filename(excludes, file):
                files.append(file.relative_to(source))

    return sorted(files)


def match_filename(regexes: Iterable[Pattern], file: Path) -> bool:
    """Check if filename matches any regular expressions."""
    for regex in regexes:
        match_ = regex.match(file.name)
        if match_ is not None:
            return True
    else:
        return False


def print_version(value: bool) -> None:
    """Print Rstash version string."""
    if value:
        print(f"Rstash {__version__}")
        sys.exit()


def sync_files(source: Path, destination: Path, manifest: Path) -> None:
    """Synchronize files with Rclone."""
    command = [
        "rclone",
        "--copy-links",
        "--human-readable",
        "copy",
    ]
    args = [
        "--no-update-dir-modtime",
        "--no-update-modtime",
        "--files-from",
        str(manifest),
        str(source),
        str(destination),
    ]
    process = subprocess.run(
        command + ["--dry-run", "--use-json-log"] + args, capture_output=True, text=True
    )
    if process.returncode != 0:
        print(process.stderr, file=sys.stderr)
        sys.exit(process.returncode)
    else:
        logs = map(json.loads, process.stderr.strip().split("\n"))
        changes = [
            f"{log['object']} -> {destination}/{log['object']}"
            for log in logs
            if "object" in log
        ]
        if not changes:
            return
        print("Changes for {}\n\n{}\n".format(destination, "\n".join(changes)))

    confirmation = typer.confirm("Sync changes (Y/n)?")
    if not confirmation:
        return

    # Multithread streams flag prevents failed to open chunk writer errors.
    task = subprocess.run(command + ["--verbose", "--multi-thread-streams", "0"] + args)
    if task.returncode != 0:
        print(task.stderr, file=sys.stderr)
        sys.exit(task.returncode)


@cli.command()
def download() -> None:
    """Download files with Rclone."""
    configs = json.loads(state["config"].read_text())
    for config in configs:
        destination = config["destination"]
        source = Path(config["source"]).expanduser().absolute()
        files = find_files(config, source)
        manifest = create_manifest(files)
        sync_files(destination, source, manifest)


@cli.callback()
def main(
    config_path: Annotated[
        Path | None, Option("-c", "--config", help="Configuration file path")
    ] = None,
    dry_run: Annotated[
        bool, Option("-d", "--dry-run", help="Only print actions to be taken")
    ] = False,
    log_level: Annotated[str, Option("-l", "--log-level", help="Log level")] = "info",
    version: Annotated[
        bool,
        Option("--version", callback=print_version, help="Print version information"),
    ] = False,
) -> None:
    """Backup files with Rclone."""
    logger.remove()
    logger.add(sys.stderr, level=log_level.upper())
    state["dry"] = dry_run
    atexit.register(clean_paths)

    if config_path is not None:
        state["config"] = config_path
    elif "RSTASH_CONFIG" in os.environ:
        state["config"] = Path(os.environ["RSTASH_CONFIG"])
    else:
        match platform.system().lower():
            case "darwin":
                state["config"] = (
                    Path.home() / "Library/Application Support/rstash/config.json"
                )
            case "windows":
                state["config"] = Path.home() / "AppData/Roaming/rstash/config.json"
            case _:
                state["config"] = Path.home() / ".config/rstash/config.json"


@cli.command()
def upload() -> None:
    """Upload files with Rclone."""
    configs = json.loads(state["config"].read_text())
    for config in configs:
        destination = config["destination"]
        source = Path(config["source"]).expanduser().absolute()
        files = find_files(config, source)
        manifest = create_manifest(files)
        sync_files(source, destination, manifest)


if __name__ == "__main__":
    cli()
