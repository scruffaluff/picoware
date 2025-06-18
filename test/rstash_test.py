"""Tests for Rstash backup script."""

from pathlib import Path
import sys

repo_path = Path(__file__).parents[1]
sys.path.append(str(repo_path / "src"))
from script import rstash  # noqa: E402


def test_create_manifest() -> None:
    """Manifest contents match files from format."""
    expected = "/foo/bar\n/foo/fake/path\n"
    files = [Path("/foo/bar"), Path("/foo/fake/path")]
    manifest = rstash.create_manifest(files)
    assert manifest.read_text() == expected
