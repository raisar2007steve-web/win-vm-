#!/usr/bin/env python3
"""Choose the newest available iPhone simulator and print shell-friendly values."""
import json
import re
import subprocess
import sys


def runtime_version(runtime: str) -> tuple:
    match = re.search(r"iOS-(\d+)(?:-(\d+))?(?:-(\d+))?", runtime)
    if not match:
        return (0, 0, 0)
    parts = [int(group) for group in match.groups() if group]
    return tuple(parts + [0] * (3 - len(parts)))


def main() -> int:
    try:
        raw = subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"], text=True)
    except subprocess.CalledProcessError as error:
        print(f"simctl failed: {error}", file=sys.stderr)
        return 1

    data = json.loads(raw)
    candidates = []
    for runtime, devices in data.get("devices", {}).items():
        if "SimRuntime.iOS-" not in runtime:
            continue
        version = runtime_version(runtime)
        for device in devices:
            if not device.get("isAvailable", True):
                continue
            name = device.get("name", "")
            if not name.startswith("iPhone"):
                continue
            # Prefer the largest screen for screenshots, but always prefer newer iOS.
            preference = 1 if ("Pro Max" in name or "Plus" in name) else 0
            candidates.append(((version, preference), name, device["udid"]))

    if not candidates:
        print("No iPhone simulator available", file=sys.stderr)
        return 1

    candidates.sort(key=lambda item: (item[0], item[1]))
    _, name, udid = candidates[-1]
    print(f"SIM_UDID={udid}")
    print(f"SIM_NAME={name}")
    print(f"SIM_RUNTIME={candidates[-1][0]}")
    print(f"DESTINATION=platform=iOS Simulator,id={udid}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
