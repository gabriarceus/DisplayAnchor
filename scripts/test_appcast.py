import copy
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET

from merge_appcast import SPARKLE, merge_appcasts


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


if __name__ == "__main__":
    unittest.main()
