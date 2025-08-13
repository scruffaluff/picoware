#!/usr/bin/env -S uv --no-config --quiet run --script
#
# /// script
# dependencies = [
#   "audioread~=3.0",
#   "cryptography~=44.0",
#   "numpy~=2.3",
#   "pywebview~=5.4",
#   "pywebview[qt]~=5.4; sys_platform == 'linux'",
#   "typer~=0.16.0",
# ]
# requires-python = "~=3.11"
# ///

"""Audio plotting example application."""

import sys
from pathlib import Path
from typing import TYPE_CHECKING, Annotated

import audioread
import numpy
import webview
from typer import Option, Typer
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
            webview.OPEN_DIALOG,
            directory=str(Path.home()),
            file_types=types,
        )
        self.samples = [self.read(file) for file in files]
        window.run_js("plot();")

    def read(self, path: str) -> list[float]:
        """Read audio file as mono signal."""
        path = Path.home() / path

        dtype = numpy.int16
        scale = numpy.abs(numpy.iinfo(dtype).min)
        with audioread.audio_open(path) as file:
            arrays = numpy.concatenate(
                [numpy.frombuffer(buffer, dtype=dtype) for buffer in file],
            )

        audio = arrays.reshape((file.channels, -1)) / scale
        samples = numpy.mean(audio, axis=0)
        times = numpy.arange(len(samples)) / file.samplerate
        return numpy.stack((times, samples)).T


def print_version(value: bool) -> None:
    """Print Rstash version string."""
    if value:
        print(f"Augraph {__version__}")
        sys.exit()


@cli.command()
def main(
    debug: Annotated[
        bool,
        Option("--debug", help="Launch application in debug mode."),
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

    html = Path(__file__).parent / "index.html"
    webview.create_window("Augraph", url=str(html), js_api=app)
    webview.start(debug=debug, gui=gui, menu=menu)


if __name__ == "__main__":
    cli()
