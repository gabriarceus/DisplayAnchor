#!/usr/bin/env python3
"""Keep the newest stable and RC items while preserving archive signatures."""

import argparse
import copy
from pathlib import Path
import re
import xml.etree.ElementTree as ET

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)


def merge_appcasts(current, previous=None):
    if not current.findall("./channel/item"):
        raise ValueError("The current release has no update item")
    latest = {}
    versions = {}
    for feed in (previous, current):
        if feed is None:
            continue
        for source in feed.findall("./channel/item"):
            item = copy.deepcopy(source)
            version = item.findtext(f"{{{SPARKLE}}}shortVersionString", "")
            if not re.fullmatch(r"\d+\.\d+\.\d+(?:-rc\d+)?", version):
                raise ValueError(f"Unsupported release version: {version}")
            build = int(item.findtext(f"{{{SPARKLE}}}version", "0"))
            enclosure = item.find("enclosure")
            if build <= 0 or enclosure is None:
                raise ValueError("Each update needs a positive build and an archive")
            signature = enclosure.get(f"{{{SPARKLE}}}edSignature")
            url = enclosure.get("url", "")
            if not signature or not url.startswith("https://"):
                raise ValueError("Each archive needs an HTTPS URL and a signature")
            if int(enclosure.get("length", "0")) <= 0:
                raise ValueError("Each archive needs a positive size")
            identity = (version, url, signature, enclosure.get("length"))
            if build in versions and versions[build] != identity:
                raise ValueError(f"Build {build} is already used by another archive")
            versions[build] = identity
            channel = "rc" if "-rc" in version else "stable"
            for old_channel in item.findall(f"{{{SPARKLE}}}channel"):
                item.remove(old_channel)
            if channel == "rc":
                ET.SubElement(item, f"{{{SPARKLE}}}channel").text = "rc"
            if channel not in latest or build > latest[channel][0]:
                latest[channel] = (build, item)

    if not latest:
        raise ValueError("No updates found")
    root = ET.Element("rss", version="2.0")
    channel = ET.SubElement(root, "channel")
    ET.SubElement(channel, "title").text = "DisplayAnchor"
    for _, item in sorted(latest.values(), key=lambda entry: entry[0], reverse=True):
        channel.append(item)
    return root


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("current", type=Path)
    parser.add_argument("previous", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    current = ET.parse(args.current).getroot()
    previous = ET.parse(args.previous).getroot() if args.previous.exists() else None
    root = merge_appcasts(current, previous)
    ET.indent(root, space="    ")
    ET.ElementTree(root).write(args.output, encoding="utf-8", xml_declaration=True)


if __name__ == "__main__":
    main()
