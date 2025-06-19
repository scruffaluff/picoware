"""Tests for Rstash backup script."""

from pathlib import Path
import sys

repo_path = Path(__file__).parents[1]
sys.path.append(str(repo_path / "src"))
from script import rstash  # noqa: E402


def test_parse_filter() -> None:
    """Strip conditional contents from filters."""
    expected = "+ /foo/bar"
    assert rstash.parse_filter(expected) == expected
