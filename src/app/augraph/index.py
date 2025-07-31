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

from pathlib import Path
import sys
from typing import Annotated

import audioread
import numpy
import webview
from typer import Option, Typer


__version__ = "0.0.1"

cli = Typer(
    add_completion=False,
    help="Audio plotting example application.",
    pretty_exceptions_enable=False,
)


class App:
    """Application backend logic."""

    def read(self, path) -> list[list[float]]:
        """Read audio file as mono signal."""
        path = Path.home() / path

        dtype = numpy.int16
        scale = numpy.abs(numpy.iinfo(dtype).min)
        with audioread.audio_open(path) as file:
            arrays = numpy.concatenate(
                [numpy.frombuffer(buffer, dtype=dtype) for buffer in file]
            )

        audio = arrays.reshape((file.channels, -1)) / scale
        samples = numpy.mean(audio, axis=0)
        times = numpy.arange(len(samples)) / file.samplerate
        return numpy.stack((times, samples)).T.tolist()


def print_version(value: bool) -> None:
    """Print Rstash version string."""
    if value:
        print(f"Augraph {__version__}")
        sys.exit()


@cli.command()
def main(
    debug: Annotated[
        bool, Option("--debug", help="Launch application in debug mode.")
    ] = False,
    version: Annotated[
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
    """Application entrypoint."""
    gui = "qt" if sys.platform == "linux" else None

    html = Path(__file__).parent / "index.html"
    app = App()
    webview.create_window("Augraph", url=str(html), js_api=app)
    webview.start(debug=debug, gui=gui)


if __name__ == "__main__":
    cli()
