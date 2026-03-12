#!/usr/bin/env python3
"""Insert a new Sparkle appcast <item> for the given release version."""

import argparse
import re
from datetime import datetime, timezone


def extract_changelog(changelog_path: str, version: str) -> str:
    """Extract release notes for a version from CHANGELOG.md and convert to HTML list items."""
    with open(changelog_path) as f:
        content = f.read()

    # Match the section for this version
    pattern = rf"## \[{re.escape(version)}\].*?\n(.*?)(?=\n## \[|\Z)"
    match = re.search(pattern, content, re.DOTALL)
    if not match:
        return "<li>See GitHub release for details.</li>"

    lines = match.group(1).strip().splitlines()
    html_lines = []
    for line in lines:
        line = line.strip()
        if not line:
            continue
        if line.startswith("### "):
            heading = line[4:]
            html_lines.append(f"<li><strong>{heading}</strong></li>")
        elif line.startswith("- "):
            item = line[2:]
            # Convert **bold** to <strong>
            item = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", item)
            # Strip markdown links [text](url) -> text
            item = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", item)
            html_lines.append(f"<li>{item}</li>")

    return (
        "\n".join(html_lines)
        if html_lines
        else "<li>See GitHub release for details.</li>"
    )


def build_item(
    version: str, tag: str, build: str, signature: str, length: str, notes_html: str
) -> str:
    """Build a Sparkle appcast <item> XML block."""
    pub_date = datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")

    return f"""        <item>
            <title>Version {version}</title>
            <description><![CDATA[
                <h2>What is New in v{version}</h2>
                <ul>
{notes_html}
                </ul>
            ]]></description>
            <pubDate>{pub_date}</pubDate>
            <sparkle:version>{build}</sparkle:version>
            <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
            <enclosure
                url="https://github.com/shreyaspapi/Oval/releases/download/{tag}/Oval-{tag}.dmg"
                sparkle:edSignature="{signature}"
                length="{length}"
                type="application/octet-stream" />
        </item>"""


def main():
    parser = argparse.ArgumentParser(description="Update Sparkle appcast.xml")
    parser.add_argument("--version", required=True, help="Version string (e.g. 1.8.0)")
    parser.add_argument("--tag", required=True, help="Git tag (e.g. v1.8.0)")
    parser.add_argument("--build", required=True, help="Build number (e.g. 14)")
    parser.add_argument("--signature", required=True, help="Sparkle EdDSA signature")
    parser.add_argument("--length", required=True, help="DMG file size in bytes")
    parser.add_argument("--changelog", required=True, help="Path to CHANGELOG.md")
    parser.add_argument("--appcast", required=True, help="Path to appcast.xml")
    args = parser.parse_args()

    notes_html = extract_changelog(args.changelog, args.version)
    new_item = build_item(
        args.version, args.tag, args.build, args.signature, args.length, notes_html
    )

    with open(args.appcast) as f:
        appcast = f.read()

    # Insert new item after <language>en</language>
    marker = "<language>en</language>"
    idx = appcast.find(marker)
    if idx == -1:
        raise SystemExit("Could not find <language>en</language> in appcast.xml")

    insert_pos = idx + len(marker)
    updated = appcast[:insert_pos] + "\n" + new_item + appcast[insert_pos:]

    with open(args.appcast, "w") as f:
        f.write(updated)

    print(f"Appcast updated with v{args.version} (build {args.build})")


if __name__ == "__main__":
    main()
