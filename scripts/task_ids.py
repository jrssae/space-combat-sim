#!/usr/bin/env python3
"""Print milestone task ids with a short description, so status messages never carry a bare id.

Usage: scripts/task_ids.py [--milestone FILE] [T05 T06 ...]   (no ids: every task in the table)
The description is the task's title from the milestone's ordered task table, cut at its first colon or parenthesis.
"""
import argparse
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def latest_milestone() -> str:
    files = sorted(glob.glob(os.path.join(ROOT, "docs", "milestones", "m*.md")),
                   key=lambda p: int(re.match(r"m(\d+)", os.path.basename(p)).group(1)))
    return files[-1]


def short_title(title: str) -> str:
    title = re.sub(r"`", "", title).strip()
    cut = re.split(r":|\s\(", title, maxsplit=1)[0].strip()
    return cut


def tasks(path: str) -> dict:
    rows = {}
    for line in open(path, encoding="utf-8"):
        m = re.match(r"\|\s*(T\d+)\s*\|[^|]*\|\s*([^|]+?)\s*\|", line)
        if m:
            rows[m.group(1)] = (short_title(m.group(2)), line.rstrip().rsplit("|", 2)[-2].strip())
    return rows


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--milestone")
    ap.add_argument("--status", action="store_true", help="append each task's Status column")
    ap.add_argument("ids", nargs="*")
    a = ap.parse_args()
    rows = tasks(a.milestone or latest_milestone())
    for tid in a.ids or sorted(rows, key=lambda t: int(t[1:])):
        tid = tid.upper().split("-")[-1]
        if tid not in rows:
            print(f"{tid} (not in the table)")
            continue
        desc, status = rows[tid]
        print(f"{tid} ({desc})" + (f"  [{status}]" if a.status else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
