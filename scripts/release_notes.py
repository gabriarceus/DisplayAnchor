#!/usr/bin/env python3
"""Build the Markdown release notes Sparkle shows for an update, from CHANGELOG.md."""

import argparse
from datetime import date
from pathlib import Path
import re

# Subsection kept in the changelog but left out of the update window.
INTERNAL_HEADING = "Maintenance"


def _sections(changelog):
    """Return (name, date or None, body) for each `## [name] - date` section, newest first."""
    parts = re.split(r"^## \[([^\]]+)\]([^\n]*)\n", changelog, flags=re.MULTILINE)
    sections = []
    for name, rest, body in zip(parts[1::3], parts[2::3], parts[3::3]):
        found = re.search(r"\d{4}-\d{2}-\d{2}", rest)
        sections.append((name, date.fromisoformat(found.group()) if found else None, body))
    return sections


def _user_facing(body):
    """Return `body` without its internal subsection."""
    kept = re.sub(rf"^### {INTERNAL_HEADING}\n.*?(?=^### |\Z)", "", body, flags=re.MULTILINE | re.DOTALL)
    return kept.strip()


def release_notes(changelog, version, count=3):
    """Return notes for `version` followed by older releases, `count` sections at most.

    The section named `version` is used, or Unreleased when it has no section yet.
    Raises ValueError when that section has no user-facing entries.
    """
    sections = _sections(changelog)
    names = [name for name, _, _ in sections]
    if version in names:
        start = names.index(version)
    elif "Unreleased" in names:
        start = names.index("Unreleased")
    else:
        start = None
    if start is None or not _user_facing(sections[start][2]):
        raise ValueError(f"No user-facing changelog notes for {version} or Unreleased")

    blocks = []
    for index, (name, released, body) in enumerate(sections[start:], start):
        notes = _user_facing(body)
        if not notes or (name == "Unreleased" and index != start):
            continue
        title = version if index == start else name
        if released:
            title += f" — {released:%b} {released.day}, {released.year}"
        blocks.append(f"## {title}\n\n{notes}")
        if len(blocks) == count:
            break
    return "\n\n".join(blocks) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("changelog", type=Path)
    parser.add_argument("version")
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    notes = release_notes(args.changelog.read_text(encoding="utf-8"), args.version)
    args.output.write_text(notes, encoding="utf-8")


if __name__ == "__main__":
    main()
