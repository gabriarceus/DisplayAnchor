#!/usr/bin/env python3
"""Extract one changelog section as plain-text notes for Sparkle."""

import argparse
from pathlib import Path
import re


def release_notes(changelog, version):
    sections = re.split(r"^## \[([^\]]+)\][^\n]*\n", changelog, flags=re.MULTILINE)
    entries = dict(zip(sections[1::2], sections[2::2]))
    notes = entries.get(version, entries.get("Unreleased", "")).strip()
    if not notes:
        raise ValueError(f"No changelog notes for {version} or Unreleased")
    notes = re.sub(r"^### (.+)$", r"\1", notes, flags=re.MULTILINE)
    notes = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", notes)
    notes = notes.replace("`", "").replace("**", "")
    notes = re.sub(r"^- ", "• ", notes, flags=re.MULTILINE)
    return notes + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("changelog", type=Path)
    parser.add_argument("version")
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.write_text(release_notes(args.changelog.read_text(encoding="utf-8"), args.version), encoding="utf-8")


if __name__ == "__main__":
    main()
