#!/usr/bin/env -S uv --no-config --quiet run --script
#
# /// script
# dependencies = [
#   "cryptography~=44.0",
#   "numpy~=2.3",
#   "pywebview~=6.0",
#   "pywebview[qt]~=6.0; sys_platform == 'linux'",
#   "soundfile~=0.13.1",
#   "tsdownsample~=0.1.4",
#   "typer~=0.21.0",
# ]
# requires-python = "~=3.11"
# ///

"""Audio plotting example application."""

from __future__ import annotations

import sys
from pathlib import Path
from subprocess import Popen
from typing import TYPE_CHECKING, Annotated

import numpy
import soundfile
import webview
from tsdownsample import LTTBDownsampler
from typer import Argument, Option, Typer
from webview.menu import Menu, MenuAction

if TYPE_CHECKING:
    from numpy.typing import NDArray

__version__ = "0.0.1"

cli = Typer(
    add_completion=False,
    help="Audio plotting example application.",
    pretty_exceptions_enable=False,
)


class App:
    """Application backend logic."""

    def __init__(self) -> None:
        """Create an App instance."""
        self.sampler = LTTBDownsampler()
        self.samples: list[NDArray] = []

    def load(self) -> list[list[float]]:
        """Convert audio samples into JavaScript compatible list."""
        samples = [sample.tolist() for sample in self.samples]
        return samples[0] if samples else []

    def open(self) -> None:
        """Audio file opener callback."""
        types = ("Audio Files (*.mp3;*.wav)",)
        window = webview.active_window()
        files = window.create_file_dialog(
            webview.FileDialog.OPEN,
            directory=str(Path.home()),
            file_types=types,
        )
        print(f"{files=}")
        self.samples = [self.read(file) for file in files]
        window.run_js("plot();")

    def read(self, path: Path) -> NDArray:
        """Read audio file as mono signal."""
        audio, rate = soundfile.read(path, always_2d=True)
        samples = numpy.mean(audio, axis=1)
        times = numpy.arange(len(samples)) / rate
        return numpy.stack((times, samples)).T


def print_version(value: bool) -> None:
    """Print Rstash version string."""
    if value:
        print(f"Augraph {__version__}")
        sys.exit()


@cli.command()
def main(
    files: Annotated[list[Path] | None, Argument(help="Audio input files")] = None,
    dev: Annotated[
        bool,
        Option("--dev", help="Launch application in developer mode."),
    ] = False,
    version: Annotated[  # noqa: ARG001
        bool,
        Option(
            "-v",
            "--version",
            callback=print_version,
            help="Print version information.",
            is_eager=True,
        ),
    ] = False,
) -> None:
    """Audio plotting example application."""
    app = App()
    gui = "qt" if sys.platform == "linux" else None
    menu = [Menu("File", [MenuAction("Open", app.open)])]
    webview.settings["OPEN_DEVTOOLS_IN_DEBUG"] = False

    for file in files or []:
        app.read(file)

    folder = Path(__file__).parent
    if dev:
        server = Popen(
            [
                "deno",
                "run",
                "--allow-all",
                "npm:vite",
                "dev",
                "--port",
                "5173",
                str(folder),
            ],
        )
        url = "http://localhost:5173"
    else:
        server = None
        url = str(folder / "index.html")

    webview.create_window("Augraph", url=url, js_api=app)
    webview.start(debug=dev, gui=gui, menu=menu)
    if server:
        server.terminate()


if __name__ == "__main__":
    cli(prog_name="augraph")
