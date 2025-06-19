#!/usr/bin/env -S uv run --script
# /// script
# dependencies = [
#   "loguru~=0.7.0",
#   "pyyaml~=6.0",
#   "typer~=0.15.0",
# ]
# requires-python = "~=3.12"
# ///

"""Backup files with Rclone."""

import functools
from itertools import chain
import json
import os
from pathlib import Path
import subprocess
import sys
import platform
from typing import Annotated, Any, Iterable

from loguru import logger
import typer
from typer import Option, Typer
import yaml


__version__ = "0.0.1"


cli = Typer(
    add_completion=False,
    help="Backup files with Rclone.",
    no_args_is_help=True,
    pretty_exceptions_enable=False,
)


state: dict[str, Any] = {"config": None, "dry": False}


class Entry:
    """Synchronization entry."""

    dest: str
    filters: list[str]
    source: str

    def __init__(
        self,
        dest: str | dict[str, str],
        source: str | dict[str, str],
        filters: list[str] | None = None,
    ) -> None:
        self.filters = filters or []

        if isinstance(dest, dict):
            option = select_option(dest)
            self.dest = Path(option).expanduser().as_posix()
        else:
            self.dest = Path(dest).expanduser().as_posix()
        if isinstance(source, dict):
            option = select_option(source)
            self.source = Path(option).expanduser().as_posix()
        else:
            self.source = Path(source).expanduser().as_posix()

    @functools.cache
    def args(self, upload: bool = True) -> list[str]:
        arguments = (["--filter", filter] for filter in self.filters)
        return list(chain(*arguments)) + [self.source, self.dest]


def fetch_changes(entries: Iterable[Entry], upload: bool = True) -> list[str]:
    command = [
        "rclone",
        "--copy-links",
        "copy",
        "--dry-run",
        "--use-json-log",
        "--no-update-dir-modtime",
        "--no-update-modtime",
    ]

    changes = []
    for entry in entries:
        process = subprocess.run(
            command + entry.args(upload),
            capture_output=True,
            text=True,
        )
        if process.returncode != 0:
            print(process.stderr, file=sys.stderr)
            sys.exit(process.returncode)
        else:
            logs = map(json.loads, process.stderr.strip().split("\n"))
            if upload:
                changes += [
                    f"{entry.source}/{log['object']} -> {entry.dest}:/{log['object']}"
                    for log in logs
                    if "object" in log
                ]
            else:
                changes += [
                    f"{entry.dest}:/{log['object']} -> {entry.source}/{log['object']}"
                    for log in logs
                    if "object" in log
                ]

    return changes


def parse_config(config: Path) -> list[Entry]:
    """Load Rstash configuration."""
    with open(config, "r") as file:
        configs = yaml.safe_load(file)
    return [Entry(**config) for config in configs]


def print_version(value: bool) -> None:
    """Print Rstash version string."""
    if value:
        print(f"Rstash {__version__}")
        sys.exit()


def select_option(options: dict[str, str]) -> str:
    """Choose most compatible option for current operating system."""
    system = platform.system().lower().replace("darwin", "macos")
    if system in options:
        return options[system]
    elif "unix" in options and system != "windows":
        return options["unix"]
    else:
        return options["default"]


def sync_changes(entries: Iterable[Entry], upload: bool = True) -> None:
    """Apply file changes."""
    # Multithread streams flag prevents failed to open chunk writer errors.
    command = [
        "rclone",
        "--copy-links",
        "--human-readable",
        "--verbose",
        "--multi-thread-streams",
        "0",
        "copy",
        "--no-update-dir-modtime",
        "--no-update-modtime",
    ]

    for entry in entries:
        task = subprocess.run(command + entry.args(upload))
        if task.returncode != 0:
            print(task.stderr, file=sys.stderr)
            sys.exit(task.returncode)


@cli.command()
def download() -> None:
    """Download files with Rclone."""
    entries = parse_config(state["config"])
    changes = fetch_changes(entries, upload=False)
    if not changes:
        return

    print("Changes to be synced.\n\n{}\n".format("\n".join(changes)))
    confirmation = typer.confirm("Sync changes (Y/n)?")
    if not confirmation:
        return
    sync_changes(entries, upload=False)


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

    if config_path is not None:
        state["config"] = config_path
    elif "RSTASH_CONFIG" in os.environ:
        state["config"] = Path(os.environ["RSTASH_CONFIG"])
    else:
        match platform.system().lower():
            case "darwin":
                state["config"] = (
                    Path.home() / "Library/Application Support/rstash/config.yaml"
                )
            case "windows":
                state["config"] = Path.home() / "AppData/Roaming/rstash/config.yaml"
            case _:
                state["config"] = Path.home() / ".config/rstash/config.yaml"


@cli.command()
def upload() -> None:
    """Upload files with Rclone."""
    entries = parse_config(state["config"])
    changes = fetch_changes(entries, upload=True)
    if not changes:
        return

    print("Changes to be synced.\n\n{}\n".format("\n".join(changes)))
    confirmation = typer.confirm("Sync changes (Y/n)?")
    if not confirmation:
        return
    sync_changes(entries, upload=True)


if __name__ == "__main__":
    cli()
