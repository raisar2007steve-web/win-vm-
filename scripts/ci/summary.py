#!/usr/bin/env python3
"""Emit a Markdown summary for the GitHub Actions job."""
import argparse
import os
import re


def failed_tests(log_path: str):
    if not os.path.exists(log_path):
        return []
    pattern = re.compile(r"Test Case '-\[([^\]]+)\]' failed")
    errors = re.compile(r"^(.*\.swift:\d+:\d+: error: .*)$")
    found, compile_errors = [], []
    with open(log_path, errors="replace") as handle:
        for line in handle:
            match = pattern.search(line)
            if match:
                found.append(match.group(1))
            compile_match = errors.match(line.strip())
            if compile_match:
                compile_errors.append(compile_match.group(1))
    return (found[:12], compile_errors[:15])


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--unit", default="skipped")
    parser.add_argument("--ui", default="skipped")
    parser.add_argument("--build", default="skipped")
    parser.add_argument("--device", default="unknown")
    parser.add_argument("--artifacts", default="ci-artifacts")
    args = parser.parse_args()

    print("\n### Results\n")
    print("| Step | Outcome |")
    print("| --- | --- |")
    print(f"| Build | {args.build} |")
    print(f"| Unit tests | {args.unit} |")
    print(f"| UI tests | {args.ui} |")
    print(f"| Simulator | {args.device} |")

    screenshots_dir = os.path.join(args.artifacts, "screenshots")
    if os.path.isdir(screenshots_dir):
        count = len([n for n in os.listdir(screenshots_dir) if n.lower().endswith(".png")])
        print(f"\nScreenshots captured: **{count}**")

    for label, filename in (("Unit", "unit-tests.log"), ("UI", "ui-tests.log"), ("Build", "build.log")):
        result = failed_tests(os.path.join(args.artifacts, filename))
        if isinstance(result, tuple):
            failures, compile_errors = result
            if failures:
                print(f"\n**{label} test failures**\n")
                for name in failures:
                    print(f"- `{name}`")
            if compile_errors:
                print(f"\n**{label} compile errors**\n")
                print("```")
                for line in compile_errors:
                    print(line)
                print("```")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
