"""Check a built Flipper zip before it is published.

Usage: python tools/verify_package.py dist/Flipper-0.2.0.zip --version 0.2.0

The zip must hold only the addon: everything under Flipper/, the TOC carrying this version,
every file the TOC lists, and nothing from the repository's tests, tools, docs or CI
(the fake auction house in tests/ is for CI only and must never ship).
"""
import argparse
import re
import sys
import zipfile

FORBIDDEN = re.compile(r"(^|/)(tests|tools|docs|\.github|dist)/|fake_wow|test_.*\.lua$|\.py$", re.IGNORECASE)
MAX_BYTES = 5 * 1024 * 1024


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("zip")
    parser.add_argument("--version", required=True)
    args = parser.parse_args()

    problems = []
    with zipfile.ZipFile(args.zip) as archive:
        names = archive.namelist()
        for name in names:
            if not name.startswith("Flipper/"):
                problems.append(f"outside the addon folder: {name}")
            if FORBIDDEN.search(name):
                problems.append(f"development file in the package: {name}")
        if "Flipper/Flipper.toc" not in names:
            problems.append("no Flipper/Flipper.toc")
        else:
            toc = archive.read("Flipper/Flipper.toc").decode("utf-8")
            if f"## Version: {args.version}" not in toc.splitlines():
                problems.append(f"TOC version is not {args.version}")
            for line in toc.splitlines():
                line = line.strip()
                if line and not line.startswith("#"):
                    path = "Flipper/" + line.replace("\\", "/")
                    if path not in names:
                        problems.append(f"TOC lists a file the zip lacks: {path}")
        size = sum(info.file_size for info in archive.infolist())
        if size > MAX_BYTES:
            problems.append(f"unpacked size {size // 1024} KB is over {MAX_BYTES // 1024} KB")

    for problem in problems:
        print("PACKAGE:", problem)
    print(f"{args.zip}: {len(names)} files, {size // 1024} KB unpacked, {len(problems)} problems")
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
