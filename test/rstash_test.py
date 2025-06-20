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
                "object": ".dictionary.txt",
                "objectType": "*local.Object",
                "size": 1834,
                "skipped": "copy",
                "source": "operations/operations.go:2570",
                "time": "2025-06-19T21:59:28.290906-07:00",
            },
            "/source/.dictionary.txt -> dest:/.dictionary.txt",
        )
    ],
)
def test_parse_logs(log: dict[str, Any], expected: str) -> None:
    """Strip conditional contents from filters."""
    # [
    #     {
    #         "level": "warning",
    #         "msg": "Skipped copy as --dry-run is set (size 1.791Ki)",
    #         "object": ".dictionary.txt",
    #         "objectType": "*local.Object",
    #         "size": 1834,
    #         "skipped": "copy",
    #         "source": "operations/operations.go:2570",
    #         "time": "2025-06-19T21:59:28.290906-07:00",
    #     },
    #     {
    #         "level": "warning",
    #         "msg": "Skipped copy as --dry-run is set (size 3.822Ki)",
    #         "object": ".justfile",
    #         "objectType": "*local.Object",
    #         "size": 3914,
    #         "skipped": "copy",
    #         "source": "operations/operations.go:2570",
    #         "time": "2025-06-19T21:59:28.29099-07:00",
    #     },
    #     {
    #         "level": "warning",
    #         "msg": "\nTransferred:   \t    5.613 KiB / 5.613 KiB, 100%, 0 B/s, ETA -\nChecks:                38 / 38, 100%\nTransferred:            2 / 2, 100%\nElapsed time:        10.2s\n\n",
    #         "source": "accounting/stats.go:528",
    #         "stats": {
    #             "bytes": 5748,
    #             "checks": 38,
    #             "deletedDirs": 0,
    #             "deletes": 0,
    #             "elapsedTime": 10.279234519,
    #             "errors": 0,
    #             "eta": None,
    #             "fatalError": False,
    #             "renames": 0,
    #             "retryError": False,
    #             "serverSideCopies": 0,
    #             "serverSideCopyBytes": 0,
    #             "serverSideMoveBytes": 0,
    #             "serverSideMoves": 0,
    #             "speed": 0,
    #             "totalBytes": 5748,
    #             "totalChecks": 38,
    #             "totalTransfers": 2,
    #             "transferTime": 0.001107307,
    #             "transfers": 2,
    #         },
    #         "time": "2025-06-19T21:59:29.110178-07:00",
    #     },
    # ]
    actual = rstash.parse_logs("/source", "dest:", [log])[0]
    assert actual == expected
