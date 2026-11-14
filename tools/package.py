"""Build dist/Flipper-<version>.zip: the Flipper folder as it goes into Interface/AddOns,
with the TOC's '## Version:' set to <version> and NOTICE alongside.

Usage: python tools/package.py --version 0.2.0
"""
import argparse
import pathlib
import re
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
ADDON = ROOT / "Flipper"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    version = parser.parse_args().version
    if not re.fullmatch(r"[0-9A-Za-z][0-9A-Za-z.+-]*", version):
        raise SystemExit(f"bad version: {version!r}")
    out = ROOT / "dist" / f"Flipper-{version}.zip"
    out.parent.mkdir(exist_ok=True)
    count = 0
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(ADDON.rglob("*")):
            if not path.is_file():
                continue
            data = path.read_bytes()
            if path.name == "Flipper.toc":
                text, replaced = re.subn(r"(?m)^## Version:.*$", f"## Version: {version}", data.decode("utf-8"))
                if replaced != 1:
                    raise SystemExit("Flipper.toc needs exactly one '## Version:' line")
                data = text.encode("utf-8")
            archive.writestr("Flipper/" + path.relative_to(ADDON).as_posix(), data)
            count += 1
        archive.writestr("Flipper/NOTICE", (ROOT / "NOTICE").read_bytes())
    print(f"{out} ({count + 1} files, {out.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
