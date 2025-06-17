#!/usr/bin/env -S uv run --script
# /// script
# dependencies = [
#   "loguru~=0.7.0",
#   "typer~=0.15.0",
# ]
# requires-python = "~=3.12"
# ///

"""Backup files with Rclone."""

import json
import os
from pathlib import Path
import re
from re import Pattern
import subprocess
import sys
import tempfile
from typing import Annotated, Iterable

from loguru import logger
from typer import Option, Typer


__version__ = "0.0.1"


cli = Typer(
    add_completion=False,
    help="Backup files with Rclone.",
    pretty_exceptions_enable=False,
)


def match(regexes: Iterable[Pattern], file: Path) -> bool:
    """Check if filename matches any regular expressions."""
    for regex in regexes:
        match_ = regex.match(file.name)
        if match_ is not None:
            return True
    else:
        return False


def sync(config: dict) -> None:
    """Backup files with Rclone."""
    destination = config["destination"]
    source = Path(config["source"]).expanduser().absolute()

    files = []
    root_excludes = [re.compile(exclude) for exclude in config.get("excludes", [])]
    root_includes = [re.compile(include) for include in config.get("includes", [])]
    for path in config["paths"]:
        if isinstance(path, dict):
            excludes = root_excludes + [
                re.compile(exclude) for exclude in path.get("excludes", [])
            ]
            includes = root_excludes + [
                re.compile(include) for include in path.get("includes", [])
            ]
            path = source / path["path"]
        else:
            excludes = root_excludes
            includes = root_includes
            path = source / path

        includes = includes or [re.compile("^.*$")]
        for file in path.iterdir():
            if match(includes, file) and not match(excludes, file):
                files.append(file.relative_to(source))

    files = sorted(files)

    file, manifest_ = tempfile.mkstemp(suffix=".txt")
    manifest = Path(manifest_).absolute()
    os.close(file)
    manifest.write_text("\n".join(map(str, files)) + "\n")

    command = [
        "rclone",
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
        print(f"Changes for {destination}\n\n{'\n'.join(changes)}\n")

    response = input("Sync changes (Y/n)? ")
    if response.lower().strip() not in ["y", "yes"]:
        return

    # Multithread streams flag prevents failed to open chunk writer errors.
    task = subprocess.run(command + ["--verbose", "--multi-thread-streams", "0"] + args)
    if task.returncode != 0:
        print(task.stderr, file=sys.stderr)
        sys.exit(task.returncode)


def version(value: bool) -> None:
    """Print Rstash version string."""
    if value:
        print(f"Rstash {__version__}")
        sys.exit()


@cli.command()
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
        Option(
            "--version",
            callback=version,
            help="Print version information",
            is_eager=True,
        ),
    ] = False,
) -> None:
    """Backup files with Rclone."""
    logger.remove()
    logger.add(sys.stderr, level=log_level.upper())

    if config_path is not None:
        config_path = config_path
    elif "RSTASH_CONFIG" in os.environ:
        config_path = Path(os.environ["RSTASH_CONFIG"])
    else:
        match sys.platform:
            case "darwin":
                config_path = (
                    Path.home() / "Library/Application Support/rstash/config.json"
                )
            case "win32":
                config_path = Path.home() / "AppData/Roaming/rstash/config.json"
            case _:
                config_path = Path.home() / ".config/rstash/config.json"

    configs = json.loads(config_path.read_text())
    for config in configs:
        sync(config)


if __name__ == "__main__":
    cli()
