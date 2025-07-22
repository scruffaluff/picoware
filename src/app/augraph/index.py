#!/usr/bin/env -S uv --no-config --quiet run --script
#
# /// script
# dependencies = [
#   "audioread~=3.0",
#   "cryptography~=44.0",
#   "numpy~=2.3",
#   "pywebview[qt]~=5.4",
#   "pywebview[qt]~=5.4; sys_platform == 'linux'",
#   "typer~=0.16.0",
# ]
# requires-python = "~=3.11"
# ///

from pathlib import Path
import sys

import audioread
import numpy
import webview
from typer import Typer


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


@cli.command()
def main(debug: bool = False) -> None:
    """Application entrypoint."""
    html = Path(__file__).parent / "index.html"
    app = App()
    webview.create_window("Augraph", url=str(html), js_api=app)
    gui = "qt" if sys.platform == "linux" else None
    webview.start(debug=debug, gui=gui)


if __name__ == "__main__":
    cli()
