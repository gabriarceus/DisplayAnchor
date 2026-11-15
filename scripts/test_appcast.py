import copy
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET

from merge_appcast import SPARKLE, merge_appcasts
from release_notes import release_notes


def feed(version, build, signature="archive-signature"):
    root = ET.Element("rss", version="2.0")
    channel = ET.SubElement(root, "channel")
    item = ET.SubElement(channel, "item")
    ET.SubElement(item, f"{{{SPARKLE}}}version").text = str(build)
    ET.SubElement(item, f"{{{SPARKLE}}}shortVersionString").text = version
    ET.SubElement(item, "enclosure", {
        "url": f"https://example.invalid/{version}.zip",
        "length": "123",
        f"{{{SPARKLE}}}edSignature": signature,
    })
    return root


class MergeAppcastTests(unittest.TestCase):
    def test_embedded_notes_survive_channel_publication(self):
        candidate = feed("1.1.0-rc4", 6)
        notes = ET.SubElement(candidate.find("./channel/item"), "description", {f"{{{SPARKLE}}}format": "markdown"})
        notes.text = "## 1.1.0-rc4\n\n### Added\n\n- Changelog in the update window."
        merged = merge_appcasts(candidate, feed("1.1.0", 5))
        published = merged.find("./channel/item/description")
        self.assertEqual(published.text, notes.text)
        self.assertEqual(published.attrib, notes.attrib)

    def test_rc_is_opt_in_and_stable_archive_signature_is_preserved(self):
        stable = feed("1.1.0", 7)
        candidate = feed("1.2.0-rc1", 8)
        original = ET.tostring(candidate)
        result = merge_appcasts(candidate, stable)
        items = result.findall("./channel/item")
        self.assertEqual(len(items), 2)
        self.assertEqual(items[0].findtext(f"{{{SPARKLE}}}channel"), "rc")
        self.assertIsNone(items[1].find(f"{{{SPARKLE}}}channel"))
        self.assertEqual(
            items[1].find("enclosure").attrib,
            stable.find("./channel/item/enclosure").attrib,
        )
        self.assertEqual(ET.tostring(candidate), original)

    def test_newer_stable_replaces_only_stable_and_old_rc_cannot_replace_new_rc(self):
        previous = merge_appcasts(feed("1.1.0", 7), feed("1.1.0-rc3", 6))
        result = merge_appcasts(feed("1.2.0", 9), previous)
        result = merge_appcasts(feed("1.1.0-rc1", 4), result)
        versions = [i.findtext(f"{{{SPARKLE}}}version") for i in result.findall("./channel/item")]
        self.assertEqual(versions, ["9", "6"])

    def test_build_reuse_and_unsigned_archives_are_rejected(self):
        with self.assertRaises(ValueError):
            merge_appcasts(feed("1.1.0", 7), feed("1.1.0-rc3", 7))
        with self.assertRaises(ValueError):
            merge_appcasts(feed("1.1.0", 7, signature=""))

    def test_rerunning_a_publication_is_idempotent(self):
        candidate = feed("1.1.0-rc3", 6)
        first = merge_appcasts(candidate)
        second = merge_appcasts(candidate, copy.deepcopy(first))
        self.assertEqual(ET.tostring(first), ET.tostring(second))

    def test_empty_current_release_cannot_silently_republish_an_old_feed(self):
        empty = ET.Element("rss", version="2.0")
        ET.SubElement(empty, "channel")
        with self.assertRaises(ValueError):
            merge_appcasts(empty, feed("1.1.0", 7))


class PublishAppcastTests(unittest.TestCase):
    def test_first_publication_and_later_channel_merge_in_an_isolated_remote(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            remote = folder / "remote.git"
            repo = folder / "repo"
            repo.mkdir()

            def git(*args, cwd=repo):
                return subprocess.run(
                    ["git", *args], cwd=cwd, check=True, text=True,
                    capture_output=True,
                ).stdout.strip()

            git("init", "--bare", str(remote))
            git("init")
            git("config", "user.name", "Appcast Test")
            git("config", "user.email", "appcast-test@example.invalid")
            git("remote", "add", "origin", str(remote))
            scripts = repo / "scripts"
            scripts.mkdir()
            for name in ("publish_appcast.sh", "merge_appcast.py"):
                shutil.copy(Path(__file__).parent / name, scripts / name)
            git("add", "scripts")
            git("commit", "-m", "Test fixture")
            source_head = git("rev-parse", "HEAD")
            current = folder / "current.xml"

            def publish(version, build):
                ET.ElementTree(feed(version, build)).write(current)
                subprocess.run(
                    ["bash", str(scripts / "publish_appcast.sh"), str(current)],
                    cwd=repo, check=True, text=True, capture_output=True,
                )

            publish("1.1.0-rc3", 6)
            publish("1.1.0", 7)
            remote_head = git("--git-dir", str(remote), "rev-parse", "updates")
            publish("1.1.0", 7)
            self.assertEqual(remote_head, git("--git-dir", str(remote), "rev-parse", "updates"))
            self.assertEqual(source_head, git("rev-parse", "HEAD"))
            self.assertEqual(git("status", "--porcelain"), "")
            self.assertEqual(git("--git-dir", str(remote), "ls-tree", "--name-only", "updates"), "appcast.xml")
            root = ET.fromstring(git("--git-dir", str(remote), "show", "updates:appcast.xml"))
            self.assertEqual(len(root.findall("./channel/item")), 2)


class ReleaseNotesTests(unittest.TestCase):
    def test_exact_version_comes_first_followed_by_older_releases(self):
        changelog = (
            "# Changelog\n\n## [Unreleased]\n\n- Future work\n\n"
            "## [1.1.0] - 2026-11-04\n\n### Added\n\n- Show **release notes** with [Sparkle](https://sparkle-project.org).\n\n"
            "## [1.0.1] - 2026-08-20\n\n### Fixed\n\n- Fix\n\n"
            "## [1.0.0] - 2026-08-11\n\n### Changed\n\n- First\n\n"
            "## [0.9.0]\n\n- Too old\n"
        )
        self.assertEqual(
            release_notes(changelog, "1.1.0"),
            "## 1.1.0 — Nov 4, 2026\n\n### New\n\n- Show **release notes** with [Sparkle](https://sparkle-project.org).\n\n"
            "## 1.0.1 — Aug 20, 2026\n\n### Bug fixes\n\n- Fix\n\n"
            "## 1.0.0 — Aug 11, 2026\n\n### Improvements\n\n- First\n",
        )

    def test_unreleased_is_titled_with_the_version_being_published(self):
        notes = release_notes(
            "## [Unreleased]\n\n### Added\n\n- New controls\n\n## [1.0.0] - 2026-08-11\n\n### Added\n\n- Old work",
            "1.1.0-rc4",
        )
        self.assertEqual(
            notes,
            "## 1.1.0-rc4\n\n### New\n\n- New controls\n\n## 1.0.0 — Aug 11, 2026\n\n### New\n\n- Old work\n",
        )

    def test_maintenance_entries_stay_out_of_the_update_window(self):
        changelog = (
            "## [Unreleased]\n\n### Fixed\n\n- Crash\n\n### Maintenance\n\n- Faster CI\n\n### Removed\n\n- Old option\n\n"
            "## [1.0.0] - 2026-08-11\n\n### Maintenance\n\n- Tooling only\n"
        )
        self.assertEqual(
            release_notes(changelog, "1.1.0"),
            "## 1.1.0\n\n### Bug fixes\n\n- Crash\n\n### Removed\n\n- Old option\n",
        )

    def test_single_release_markdown_omits_version_heading_and_adds_sha256_footer(self):
        changelog = (
            "## [1.1.0] - 2026-11-04\n\n"
            "Release summary.\n\n"
            "### Added\n\n- Feature\n  - Sub-detail\n\n"
            "## [1.0.0] - 2026-08-11\n\n- Old\n"
        )
        notes = release_notes(changelog, "1.1.0", count=1, sha256="abc123")
        self.assertEqual(
            notes,
            "Release summary.\n\n"
            "### New\n\n- Feature\n  - Sub-detail\n\n"
            "---\n\n"
            "**Requires macOS 26 or later** (Universal Binary for Apple Silicon and Intel).\n"
            "**SHA-256:** `abc123`\n",
        )

    def test_html_renders_badges_inline_formatting_sublists_and_collapsible_older_releases(self):
        changelog = (
            "## [1.2.0] - 2026-11-05\n\n"
            "### Added\n\n"
            "- Added **notes** with `code` and [Sparkle](https://sparkle-project.org).\n"
            "  - Indented detail\n\n"
            "### Changed\n\n"
            "- Faster checks.\n\n"
            "### Fixed\n\n"
            "- Escaped <angle> brackets.\n\n"
            "### Removed\n\n"
            "- Legacy mode.\n\n"
            "### Maintenance\n\n"
            "- Internal cleanup.\n\n"
            "## [1.1.0] - 2026-11-04\n\n"
            "Older intro.\n\n"
            "### Fixed\n\n"
            "- Previous fix.\n"
        )
        html_notes = release_notes(changelog, "1.2.0", fmt="html")
        self.assertNotIn("<!DOCTYPE", html_notes)
        self.assertNotIn("<body", html_notes)
        self.assertIn("<h1>DisplayAnchor 1.2.0</h1>", html_notes)
        self.assertIn('<span class="badge badge-added">NEW</span>', html_notes)
        self.assertIn('<span class="badge badge-changed">IMPROVE</span>', html_notes)
        self.assertIn('<span class="badge badge-fixed">FIX</span>', html_notes)
        self.assertIn('<span class="badge badge-removed">REMOVED</span>', html_notes)
        self.assertIn("<strong>notes</strong>", html_notes)
        self.assertIn("<code>code</code>", html_notes)
        self.assertIn('<a href="https://sparkle-project.org">Sparkle</a>', html_notes)
        self.assertIn('<ul class="note-sublist"><li>Indented detail</li></ul>', html_notes)
        self.assertIn("Escaped &lt;angle&gt; brackets.", html_notes)
        self.assertNotIn("Internal cleanup", html_notes)
        self.assertIn("<h2>DisplayAnchor 1.1.0</h2>", html_notes)
        self.assertIn("<p>Older intro.</p>", html_notes)
        self.assertIn("<details>\n<summary>Show DisplayAnchor 1.1.0 release notes</summary>", html_notes)
        self.assertIn("Previous fix.", html_notes)

    def test_missing_or_internal_only_notes_fail_instead_of_publishing_an_empty_window(self):
        for changelog in (
            "# Changelog",
            "## [Unreleased]\n\n## [1.0.0]\n\n- Old work",
            "## [Unreleased]\n\n### Maintenance\n\n- Tooling only\n",
        ):
            with self.assertRaises(ValueError):
                release_notes(changelog, "1.1.0-rc4")


if __name__ == "__main__":
    unittest.main()
