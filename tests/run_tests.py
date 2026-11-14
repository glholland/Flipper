"""Run Flipper's offline Lua tests under Lua 5.1 (lupa).

Usage:
    python tests/run_tests.py            # logic tests
    python tests/run_tests.py --syntax   # also load every addon file with WoW stubs

Requires: pip install lupa
"""
import pathlib
import sys

try:
    from lupa import lua51
except ImportError:
    sys.exit("lupa is not installed: pip install lupa")

ROOT = pathlib.Path(__file__).resolve().parent.parent
ADDON = ROOT / "Flipper"


def toc_files():
    files = []
    for line in (ADDON / "Flipper.toc").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            files.append(ADDON / line.replace("\\", "/"))
    return files


def load(lua, ns, path):
    chunk = lua.execute(
        "return function(src, name) return assert(loadstring(src, name)) end"
    )(path.read_text(encoding="utf-8"), "@" + path.name)
    return chunk("Flipper", ns)


def main():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    ns = lua.table()
    # Pure modules only need these.
    for name in ("Core/Init.lua", "Core/Money.lua", "Core/Logic.lua", "Core/Disenchant.lua"):
        load(lua, ns, ADDON / name)
    test = lua.execute(
        "return function(src) return assert(loadstring(src, '@test_logic.lua')) end"
    )((ROOT / "tests" / "test_logic.lua").read_text(encoding="utf-8"))
    passed, failures = test(ns)
    failures = list(failures.values()) if failures else []
    for f in failures:
        print("FAIL", f)
    print(f"{passed} passed, {len(failures)} failed")

    if "--syntax" in sys.argv:
        bad = 0
        compile_ = lua.execute("return function(src, n) local f, e = loadstring(src, n) return e end")
        for path in toc_files():
            err = compile_(path.read_text(encoding="utf-8"), "@" + path.name)
            if err:
                bad += 1
                print("SYNTAX", err)
        print(f"syntax: {len(toc_files()) - bad} ok, {bad} bad")
        failures += [None] * bad

    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
