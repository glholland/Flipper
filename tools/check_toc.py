"""Check Flipper.toc against the files on disk: every listed file exists (exact case) and
every Lua file in the addon folder is listed. Exits 1 on any mismatch."""
import pathlib
import re
import sys

ADDON = pathlib.Path(__file__).resolve().parent.parent / "Flipper"


def main():
    toc = (ADDON / "Flipper.toc").read_text(encoding="utf-8").splitlines()
    problems = []
    if not any(line.startswith("## Interface:") for line in toc):
        problems.append("no '## Interface:' line")
    if not any(line.startswith("## Version:") for line in toc):
        problems.append("no '## Version:' line")
    listed = [line.strip().replace("\\", "/") for line in toc if line.strip() and not line.startswith("#")]
    on_disk = {p.relative_to(ADDON).as_posix() for p in ADDON.rglob("*.lua")}
    for name in listed:
        if name not in on_disk:
            problems.append(f"listed but missing (check the case too): {name}")
    for name in sorted(on_disk - set(listed)):
        problems.append(f"on disk but not in the TOC: {name}")
    # The addon menu calls the functions the TOC names: each must be defined as a global.
    source = "\n".join((ADDON / name).read_text(encoding="utf-8") for name in listed if name in on_disk)
    for line in toc:
        match = re.match(r"## AddonCompartmentFunc\w*:\s*(\S+)", line)
        if match and not re.search(r"^function " + re.escape(match.group(1)) + r"\(", source, re.M):
            problems.append(f"TOC names {match.group(1)} but no file defines it")
    if len(listed) != len(set(listed)):
        problems.append("a file is listed twice")
    for problem in problems:
        print("TOC:", problem)
    print(f"{len(listed)} files listed, {len(problems)} problems")
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
