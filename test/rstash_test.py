"""Tests for Rstash backup script."""

from pathlib import Path
import sys
from typing import Any

import pytest

repo_path = Path(__file__).parents[1]
sys.path.append(str(repo_path / "src"))
from script import rstash  # noqa: E402


@pytest.mark.parametrize(
    "log,expected",
    [
        (
            {
                "level": "warning",
                "msg": "Skipped copy as --dry-run is set (size 1.791Ki)",
                "object": "file.txt",
                "objectType": "*local.Object",
                "size": 1834,
                "skipped": "copy",
                "source": "operations/operations.go:2570",
                "time": "2025-06-19T21:59:28.290906-07:00",
            },
            "/source/file.txt -> dest:/file.txt",
        )
    ],
)
def test_parse_logs(log: dict[str, Any], expected: str) -> None:
    """Map Rclone logs to file transfers."""
    actual = rstash.parse_logs("/source", "dest:", [log])[0]
    assert actual == expected
