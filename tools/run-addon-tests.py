#!/usr/bin/env python3
"""Run a trusted addon test entry point with Lupa's actual Lua 5.1 runtime.

Install the optional runtime locally (not into the addon or global Python):
    py -m pip install --require-hashes --only-binary=:all: --target .release/test-deps \
        -r tools/requirements-addon-tests.txt

Run from any directory; Lua relative paths resolve from the workspace root.
The tests supply their own WoW mocks. This is not an in-game compatibility test.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import sys


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("script", nargs="?", default="tests/palantir/run.lua")
    parser.add_argument(
        "--deps",
        type=Path,
        default=Path(".release/test-deps"),
        help="Lupa installation directory, relative to the workspace root",
    )
    args = parser.parse_args()
    script = (root / args.script).resolve()
    if not script.is_file():
        print(f"Test entry point not found: {script}", file=sys.stderr)
        return 2

    deps = (root / args.deps).resolve()
    sys.path.insert(0, str(deps))
    try:
        from lupa.lua51 import LuaError, LuaRuntime
    except ImportError as error:
        print(
            f"Lua 5.1 test runtime unavailable for this Python ({sys.executable}).\n"
            f"{error}\n"
            "Install it with the same Python interpreter used to run this script:\n"
            f'  "{sys.executable}" -m pip install --require-hashes --only-binary=:all: '
            f'--target "{deps}" -r "{root / "tools/requirements-addon-tests.txt"}"',
            file=sys.stderr,
        )
        return 2

    os.chdir(root)
    lua = LuaRuntime(
        unpack_returned_tuples=True, register_eval=False, register_builtins=False
    )
    version = lua.eval("_VERSION")
    if version != "Lua 5.1":
        print(f"Expected Lua 5.1, received {version}", file=sys.stderr)
        return 2
    lua.globals().arg = lua.table_from({0: script.as_posix()})
    print(f"Running {script.name} with {lua.lua_implementation}", flush=True)
    try:
        lua.eval("function(path) return assert(loadfile(path))() end")(
            script.as_posix()
        )
    except (LuaError, OSError) as error:
        print(f"{error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
