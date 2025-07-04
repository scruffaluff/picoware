#!/usr/bin/env -S uv --quiet run --script
# /// script
# dependencies = [
#   "loguru~=0.7.0",
#   "pyyaml~=6.0",
#   "typer~=0.15.0",
# ]
# requires-python = "~=3.12"
# ///

"""Rclone wrapper for interactive and conditional backups."""

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


__version__ = "0.0.3"

cli = Typer(
    add_completion=False,
    help="Rclone wrapper for interactive and conditional backups.",
    no_args_is_help=True,
    pretty_exceptions_enable=False,
)

# Use Rclone environment variables to avoid unsupported flags on specific versions.
os.environ["RCLONE_COPY_LINKS"] = "true"
os.environ["RCLONE_HUMAN_READABLE"] = "true"
os.environ["RCLONE_NO_UPDATE_DIR_MODTIME"] = "true"

# Shared state to hold global application flags.
state: dict[str, Any] = {"config": None, "dry_run": False}


class Manifest:
    """Synchronization and location details."""

    arguments: list[str]
    dest: str
    filters: list[str]
    source: str

    def __init__(
        self,
        dest: str | dict[str, str],
        source: str | dict[str, str],
        args: list[str] | None = None,
        filters: list[str] | None = None,
    ) -> None:
        self.arguments = args or []
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
        """Create Rclone synchronization arguments."""
        arguments = (["--filter", filter] for filter in self.filters)
        if upload:
            return list(chain(*arguments)) + self.arguments + [self.source, self.dest]
        else:
            return list(chain(*arguments)) + self.arguments + [self.dest, self.source]


def compute_changes(
    manifests: Iterable[Manifest], upload: bool = True
) -> tuple[list[Manifest], str]:
    """Dry run synchronizations to assemble list of changes."""
    records = []
    changes = ""

    for manifest in manifests:
        if upload:
            source, dest = manifest.source, manifest.dest
        else:
            source, dest = manifest.dest, manifest.source

        process = subprocess.run(
            ["rclone", "--dry-run", "--use-json-log", "copy", "--update"]
            + manifest.args(upload),
            capture_output=True,
            text=True,
        )
        if process.returncode != 0:
            print(process.stderr, file=sys.stderr)
            sys.exit(process.returncode)

        logs = map(json.loads, process.stderr.strip().split("\n"))
        change = parse_logs(source, dest, logs)
        if change:
            records.append(manifest)
            changes = "{}\n{}".format(changes, "\n".join(change))

    return records, changes


def load_config(config: Path) -> list[Manifest]:
    """Load Rstash configuration."""
    with open(config, "r") as file:
        configs = yaml.safe_load(file)
    return [Manifest(**config) for config in configs]


def parse_logs(source: str, dest: str, logs: Iterable[dict]) -> list[str]:
    """Parse Rclone logs for synchronization changes."""
    messages = []
    for log in logs:
        if "object" in log:
            messages.append(f"{source}/{log['object']} -> {dest}/{log['object']}")
    return messages


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


def sync_changes(manifests: Iterable[Manifest], upload: bool = True) -> None:
    """Apply synchronization changes."""
    for manifest in manifests:
        task = subprocess.run(
            ["rclone", "--verbose", "copy", "--update"] + manifest.args(upload)
        )
        if task.returncode != 0:
            print(task.stderr, file=sys.stderr)
            sys.exit(task.returncode)


@cli.command()
def download() -> None:
    """Download files with Rclone."""
    manifests = load_config(state["config"])
    for manifest in manifests:
        Path(manifest.source).mkdir(exist_ok=True, parents=True)

    manifests, changes = compute_changes(manifests, upload=False)
    if not manifests:
        return

    print("Changes to be synced.\n{}\n".format(changes))
    if state["dry_run"]:
        return
    confirm = typer.confirm("Sync changes?")
    if confirm:
        sync_changes(manifests, upload=False)


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
    """Rclone wrapper for interactive and conditional backups."""
    logger.remove()
    logger.add(sys.stderr, level=log_level.upper())
    state["dry_run"] = dry_run

    if config_path is not None:
        state["config"] = config_path
    elif "RSTASH_CONFIG" in os.environ:
        state["config"] = Path(os.environ["RSTASH_CONFIG"])
    else:
        match platform.system().lower():
            case "darwin":
                state["config"] = (
                    Path.home() / "Library/Application Support/rstash/rstash.yaml"
                )
            case "windows":
                state["config"] = Path.home() / "AppData/Roaming/rstash/rstash.yaml"
            case _:
                state["config"] = Path.home() / ".config/rstash/rstash.yaml"


@cli.command()
def sync() -> None:
    """Sync files with Rclone."""
    manifests = load_config(state["config"])
    for manifest in manifests:
        Path(manifest.source).mkdir(exist_ok=True, parents=True)

    downloads = compute_changes(manifests, upload=False)
    uploads = compute_changes(manifests, upload=True)
    manifests = downloads[0] + uploads[0]
    changes = downloads[1] + uploads[1]
    if not manifests:
        return

    print("Changes to be synced.\n{}\n".format(changes))
    if state["dry_run"]:
        return
    confirm = typer.confirm("Sync changes?")
    if confirm:
        sync_changes(downloads[0], upload=False)
        sync_changes(uploads[0], upload=True)


@cli.command()
def upload() -> None:
    """Upload files with Rclone."""
    manifests = load_config(state["config"])
    manifests, changes = compute_changes(manifests, upload=True)
    if not manifests:
        return

    print("Changes to be synced.\n{}\n".format(changes))
    if state["dry_run"]:
        return
    confirm = typer.confirm("Sync changes?")
    if confirm:
        sync_changes(manifests, upload=True)


if __name__ == "__main__":
    cli()
