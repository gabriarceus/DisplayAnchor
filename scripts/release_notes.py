#!/usr/bin/env python3
"""Build Sparkle (HTML) and GitHub Release (Markdown) notes from CHANGELOG.md."""

import argparse
from datetime import date
import html
from pathlib import Path
import re

# Subsection kept in the changelog but left out of published release notes.
INTERNAL_HEADING = "Maintenance"

# Maps Keep a Changelog headings to user-facing titles and Sparkle badge tokens.
CATEGORY_META = {
    "Added": ("New", "NEW", "added"),
    "Changed": ("Improvements", "IMPROVE", "changed"),
    "Fixed": ("Bug fixes", "FIX", "fixed"),
    "Removed": ("Removed", "REMOVED", "removed"),
}

_INLINE_RE = re.compile(r"`([^`]+)`|\*\*([^*]+)\*\*|\[([^\]]+)\]\(([^)\s]+)\)")
_BULLET_RE = re.compile(r"^( *)[-*]\s+(.*)$")

_HTML_STYLES = """<style>
.release-notes {
    font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
    font-size: 13px;
    line-height: 1.5;
}
.release-notes h1 {
    font-size: 20px;
    font-weight: 700;
    margin: 0 0 12px;
    padding-bottom: 8px;
    border-bottom: 1px solid rgba(128, 128, 128, 0.35);
}
.release-notes h2 {
    font-size: 16px;
    font-weight: 700;
    margin: 0 0 10px;
}
.release-notes h3 {
    font-size: 14px;
    font-weight: 600;
    margin: 14px 0 8px;
}
.release-notes p {
    margin: 0 0 10px;
}
.release-notes hr {
    border: 0;
    border-top: 1px solid rgba(128, 128, 128, 0.35);
    margin: 16px 0;
}
.release-notes code {
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 12px;
    padding: 1px 4px;
    border-radius: 4px;
    background: rgba(128, 128, 128, 0.2);
}
.release-notes .note-list {
    display: flex;
    flex-direction: column;
    gap: 6px;
    margin: 0 0 10px;
}
.release-notes .note-item {
    display: flex;
    align-items: baseline;
    gap: 8px;
}
.release-notes .badge {
    display: inline-block;
    flex-shrink: 0;
    padding: 1px 6px;
    border-radius: 3px;
    font-size: 10px;
    font-weight: 700;
    letter-spacing: 0.03em;
    line-height: 1.4;
    color: #ffffff;
    text-transform: uppercase;
}
.release-notes .badge-added { background: #2da44e; }
.release-notes .badge-changed { background: #6e40c9; }
.release-notes .badge-fixed { background: #d97706; }
.release-notes .badge-removed { background: #cf222e; }
.release-notes .note-text {
    flex: 1;
    min-width: 0;
}
.release-notes .note-sublist {
    margin: 4px 0 0;
    padding-left: 14px;
    list-style-type: none;
}
.release-notes .note-sublist li::before {
    content: "– ";
    opacity: 0.75;
}
.release-notes .plain-list {
    margin: 0 0 10px;
    padding-left: 20px;
}
.release-notes details {
    margin: 8px 0 0;
}
.release-notes summary {
    cursor: pointer;
    font-weight: 500;
    user-select: none;
}
.release-notes details[open] summary {
    margin-bottom: 10px;
}
</style>"""


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


def _parse_blocks(lines):
    """Parse paragraphs and nested bullet lists from raw Markdown lines."""
    blocks = []
    para_lines = []
    current_list = None

    def flush_para():
        if para_lines:
            blocks.append(("paragraph", " ".join(para_lines)))
            para_lines.clear()

    def flush_list():
        nonlocal current_list
        if current_list is not None:
            blocks.append(("list", current_list))
            current_list = None

    for raw_line in lines:
        stripped = raw_line.strip()
        if not stripped:
            flush_para()
            flush_list()
            continue
        match = _BULLET_RE.match(raw_line)
        if match:
            indent = len(match.group(1))
            item_text = match.group(2).strip()
            flush_para()
            if indent >= 2 and current_list:
                current_list[-1][1].append(item_text)
            else:
                if current_list is None:
                    current_list = []
                current_list.append((item_text, []))
        elif current_list is not None and raw_line.startswith("  "):
            if current_list[-1][1]:
                current_list[-1][1][-1] += " " + stripped
            else:
                parent, subs = current_list[-1]
                current_list[-1] = (parent + " " + stripped, subs)
        else:
            flush_list()
            para_lines.append(stripped)

    flush_para()
    flush_list()
    return blocks


def _parse_section_content(body):
    """Split a release body into intro blocks and (heading, blocks) subsections."""
    parts = re.split(r"^### ([^\n]+)\n", body + "\n", flags=re.MULTILINE)
    intro_blocks = _parse_blocks(parts[0].splitlines())
    subsections = []
    for heading, sub_body in zip(parts[1::2], parts[2::2]):
        blocks = _parse_blocks(sub_body.splitlines())
        if blocks:
            subsections.append((heading.strip(), blocks))
    return intro_blocks, subsections


def _render_inline_html(text):
    """Convert inline Markdown (`code`, **bold**, [label](https-url)) to escaped HTML."""
    out = []
    last = 0
    for match in _INLINE_RE.finditer(text):
        out.append(html.escape(text[last : match.start()]))
        if match.group(1) is not None:
            out.append(f"<code>{html.escape(match.group(1))}</code>")
        elif match.group(2) is not None:
            out.append(f"<strong>{html.escape(match.group(2))}</strong>")
        else:
            label, url = match.group(3), match.group(4)
            if url.startswith(("https://", "http://")):
                out.append(f'<a href="{html.escape(url, quote=True)}">{html.escape(label)}</a>')
            else:
                out.append(html.escape(match.group(0)))
        last = match.end()
    out.append(html.escape(text[last:]))
    return "".join(out)


def _render_markdown_blocks(blocks):
    parts = []
    for kind, data in blocks:
        if kind == "paragraph":
            parts.append(data)
        else:
            lines = []
            for item, subs in data:
                lines.append(f"- {item}")
                for sub in subs:
                    lines.append(f"  - {sub}")
            parts.append("\n".join(lines))
    return parts


def _render_release_markdown(intro_blocks, subsections):
    parts = _render_markdown_blocks(intro_blocks)
    for heading, blocks in subsections:
        title = CATEGORY_META[heading][0] if heading in CATEGORY_META else heading
        sub_parts = [f"### {title}"] + _render_markdown_blocks(blocks)
        parts.append("\n\n".join(sub_parts))
    return "\n\n".join(parts)


def _render_html_blocks(blocks, badge=None):
    parts = []
    for kind, data in blocks:
        if kind == "paragraph":
            parts.append(f"<p>{_render_inline_html(data)}</p>")
        elif badge is not None:
            badge_label, badge_class = badge
            rows = []
            for item, subs in data:
                sub_html = ""
                if subs:
                    sub_items = "".join(f"<li>{_render_inline_html(sub)}</li>" for sub in subs)
                    sub_html = f'<ul class="note-sublist">{sub_items}</ul>'
                rows.append(
                    f'<div class="note-item">'
                    f'<span class="badge badge-{badge_class}">{badge_label}</span>'
                    f'<div class="note-text">{_render_inline_html(item)}{sub_html}</div>'
                    f"</div>"
                )
            parts.append('<div class="note-list">\n' + "\n".join(rows) + "\n</div>")
        else:
            items = []
            for item, subs in data:
                sub_html = ""
                if subs:
                    sub_items = "".join(f"<li>{_render_inline_html(sub)}</li>" for sub in subs)
                    sub_html = f'<ul class="note-sublist">{sub_items}</ul>'
                items.append(f"<li>{_render_inline_html(item)}{sub_html}</li>")
            parts.append('<ul class="plain-list">\n' + "\n".join(items) + "\n</ul>")
    return parts


def _render_html_subsections(subsections):
    parts = []
    for heading, blocks in subsections:
        if heading in CATEGORY_META:
            title, badge_label, badge_class = CATEGORY_META[heading]
            badge = (badge_label, badge_class)
        else:
            title = heading
            badge = None
        parts.append(f"<h3>{html.escape(title)}</h3>")
        parts.extend(_render_html_blocks(blocks, badge=badge))
    return parts


def release_notes(changelog, version, count=3, fmt="markdown", sha256=None):
    """Return formatted release notes for `version` and up to `count - 1` older releases.

    The section named `version` is used, or Unreleased when it has no section yet.
    Raises ValueError when that section has no user-facing entries or `fmt` is unknown.
    """
    if fmt not in ("markdown", "html"):
        raise ValueError(f"Unsupported output format: {fmt}")

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

    selected = []
    for index, (name, released, body) in enumerate(sections[start:], start):
        notes = _user_facing(body)
        if not notes or (name == "Unreleased" and index != start):
            continue
        display_version = version if index == start else name
        intro_blocks, subsections = _parse_section_content(notes)
        selected.append((display_version, released, intro_blocks, subsections))
        if len(selected) == count:
            break

    if fmt == "html":
        return _format_html(selected)
    return _format_markdown(selected, include_heading=count != 1, sha256=sha256)


def _format_markdown(selected, include_heading, sha256):
    blocks = []
    for display_version, released, intro_blocks, subsections in selected:
        rendered = _render_release_markdown(intro_blocks, subsections)
        if include_heading:
            title = display_version
            if released:
                title += f" — {released:%b} {released.day}, {released.year}"
            blocks.append(f"## {title}\n\n{rendered}")
        else:
            blocks.append(rendered)
    output = "\n\n".join(blocks)
    if sha256:
        output += (
            "\n\n---\n\n"
            "**Requires macOS 26 or later** (Universal Binary for Apple Silicon and Intel).\n"
            f"**SHA-256:** `{sha256}`"
        )
    return output + "\n"


def _format_html(selected):
    # Emit an HTML fragment without DOCTYPE or body tags so Sparkle's generate_appcast
    # embeds it cleanly inside CDATA and applies its own light/dark base stylesheet.
    parts = [_HTML_STYLES, '<div class="release-notes">']
    for index, (display_version, _, intro_blocks, subsections) in enumerate(selected):
        escaped_version = html.escape(display_version)
        if index == 0:
            parts.append(f"<h1>DisplayAnchor {escaped_version}</h1>")
            parts.extend(_render_html_blocks(intro_blocks))
            parts.extend(_render_html_subsections(subsections))
        else:
            parts.append("<hr>")
            parts.append(f"<h2>DisplayAnchor {escaped_version}</h2>")
            intro_paragraphs = [block for block in intro_blocks if block[0] == "paragraph"]
            extra_blocks = [block for block in intro_blocks if block[0] != "paragraph"]
            parts.extend(_render_html_blocks(intro_paragraphs))
            detail_parts = _render_html_blocks(extra_blocks) + _render_html_subsections(subsections)
            if detail_parts:
                parts.append(f"<details>\n<summary>Show DisplayAnchor {escaped_version} release notes</summary>")
                parts.extend(detail_parts)
                parts.append("</details>")
    parts.append("</div>")
    return "\n".join(parts) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("changelog", type=Path)
    parser.add_argument("version")
    parser.add_argument("output", type=Path)
    parser.add_argument(
        "--count",
        type=int,
        default=3,
        help="Number of release sections to include (default: 3).",
    )
    parser.add_argument(
        "--format",
        choices=("auto", "markdown", "html"),
        default="auto",
        help="Output format (default: inferred from output extension).",
    )
    parser.add_argument(
        "--sha256",
        default=None,
        help="Optional archive SHA-256 digest appended to Markdown output.",
    )
    args = parser.parse_args()
    fmt = args.format
    if fmt == "auto":
        fmt = "html" if args.output.suffix.lower() in (".html", ".htm") else "markdown"
    notes = release_notes(
        args.changelog.read_text(encoding="utf-8"),
        args.version,
        count=args.count,
        fmt=fmt,
        sha256=args.sha256,
    )
    args.output.write_text(notes, encoding="utf-8")


if __name__ == "__main__":
    main()
