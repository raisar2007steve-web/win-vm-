#!/usr/bin/env python3
"""Export XCTAttachment screenshots from an .xcresult bundle into the gallery folder."""
import json
import os
import shutil
import subprocess
import sys
import tempfile


def walk_manifest(node, collected):
    if isinstance(node, dict):
        exported = node.get("exportedFileName")
        human = node.get("suggestedHumanReadableName") or node.get("name")
        if exported and human:
            collected.append((human, exported))
        for value in node.values():
            walk_manifest(value, collected)
    elif isinstance(node, list):
        for item in node:
            walk_manifest(item, collected)


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: collect_xcresult_screenshots.py <xcresult> <output-dir>")
        return 2

    xcresult, output = sys.argv[1], sys.argv[2]
    if not os.path.isdir(xcresult):
        print(f"No result bundle at {xcresult}")
        return 0
    os.makedirs(output, exist_ok=True)

    with tempfile.TemporaryDirectory() as staging:
        result = subprocess.run(
            ["xcrun", "xcresulttool", "export", "attachments", "--path", xcresult, "--output-path", staging],
            text=True,
            capture_output=True,
        )
        if result.returncode != 0:
            print("xcresulttool export failed:")
            print(result.stdout[-2000:])
            print(result.stderr[-2000:])
            return 0

        manifest_path = os.path.join(staging, "manifest.json")
        pairs = []
        if os.path.exists(manifest_path):
            with open(manifest_path) as handle:
                walk_manifest(json.load(handle), pairs)

        exported = set()
        for human, exported_name in pairs:
            source = os.path.join(staging, exported_name)
            if not os.path.exists(source):
                continue
            clean = "".join(ch if ch.isalnum() or ch in "-_" else "-" for ch in human).strip("-")
            target_name = f"ui-{clean or 'screenshot'}.png"
            if not target_name.endswith(".png"):
                target_name += ".png"
            shutil.copyfile(source, os.path.join(output, target_name))
            exported.add(exported_name)
            print(f"exported {human} -> {target_name}")

        # Fall back to any loose images if the manifest shape was unexpected.
        for name in os.listdir(staging):
            if name in exported:
                continue
            if name.lower().endswith((".png", ".jpg", ".jpeg")):
                shutil.copyfile(os.path.join(staging, name), os.path.join(output, f"ui-{name}"))
                print(f"exported raw {name}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
