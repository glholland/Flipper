"""Work out the version and tag for a release, from the existing v* tags.

Usage:
  python tools/next_version.py --bump minor             # 0.2.0 -> 0.3.0
  python tools/next_version.py --version 1.0.0          # exactly this
  python tools/next_version.py --bump patch --prerelease   # 0.2.1-beta.1, then -beta.2 ...
  python tools/next_version.py --tag v0.3.0             # check a tag someone pushed

Prints version=, tag=, previous_tag=, prerelease= lines, and appends them to
$GITHUB_OUTPUT when set. Exits 1 if the version is malformed, not newer than the latest
release, or already tagged.
"""
import argparse
import os
import re
import subprocess
import sys

SEMVER = re.compile(r"^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?$")
FIRST_BASE = (0, 1, 0)    # the version in Flipper.toc before the first release


def parse(version):
    m = SEMVER.match(version)
    if not m:
        return None
    return (int(m[1]), int(m[2]), int(m[3])), m[4]


def tags():
    out = subprocess.run(["git", "tag", "--list", "v*"], capture_output=True, text=True, check=True).stdout
    found = []
    for tag in out.split():
        parsed = parse(tag[1:])
        if parsed:
            found.append((parsed[0], parsed[1], tag))
    return found


def sort_key(item):
    core, pre, _ = item
    # A pre-release sorts before its final release.
    return core, 0 if pre else 1, pre or ""


def fail(message):
    print("error: " + message, file=sys.stderr)
    sys.exit(1)


def main():
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--bump", choices=["patch", "minor", "major"])
    group.add_argument("--version")
    group.add_argument("--tag")
    parser.add_argument("--prerelease", action="store_true")
    args = parser.parse_args()

    existing = sorted(tags(), key=sort_key)
    names = {t for _, _, t in existing}
    stable = [t for t in existing if not t[1]]
    latest = stable[-1][0] if stable else FIRST_BASE

    if args.tag:
        parsed = parse(args.tag[1:]) if args.tag.startswith("v") else None
        if not parsed:
            fail(f"{args.tag} is not a v<major>.<minor>.<patch> tag")
        version, core, pre = args.tag[1:], parsed[0], parsed[1]
        previous = [t for t in existing if t[2] != args.tag and sort_key(t) < sort_key((core, pre, ""))]
    else:
        if args.version:
            parsed = parse(args.version)
            if not parsed:
                fail(f"{args.version} is not <major>.<minor>.<patch>[-pre]")
            core, pre = parsed
        else:
            major, minor, patch = latest
            core = {"major": (major + 1, 0, 0), "minor": (major, minor + 1, 0), "patch": (major, minor, patch + 1)}[args.bump]
            pre = None
        if args.prerelease and not pre:
            n = 1
            while f"v{'.'.join(map(str, core))}-beta.{n}" in names:
                n += 1
            pre = f"beta.{n}"
        if core <= latest and stable:
            fail(f"{'.'.join(map(str, core))} is not newer than the latest release v{'.'.join(map(str, latest))}")
        version = ".".join(map(str, core)) + (f"-{pre}" if pre else "")
        if f"v{version}" in names:
            fail(f"v{version} is already tagged")
        previous = existing

    tag = f"v{version}"
    previous_tag = previous[-1][2] if previous else ""
    lines = [f"version={version}", f"tag={tag}", f"previous_tag={previous_tag}",
             f"prerelease={'true' if pre else 'false'}"]
    print("\n".join(lines))
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as out:
            out.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
