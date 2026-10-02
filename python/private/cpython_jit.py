"""Run CPython's stencil generator using declared Bazel inputs."""

import argparse
import json
import os
from pathlib import Path
import re
import runpy
import shlex
import sys

parser = argparse.ArgumentParser()
parser.add_argument("--script", required=True, type=Path)
parser.add_argument("--output", required=True, type=Path)
parser.add_argument("--pyconfig", required=True, type=Path)
parser.add_argument("--tools", required=True, type=Path)
parser.add_argument("--glibc", required=True, type=Path)
parser.add_argument("--kernel", required=True, type=Path)
parser.add_argument("--resource", required=True, type=Path)
parser.add_argument("--extra-headers", required=True, type=Path)
parser.add_argument("--target", required=True)
args = parser.parse_args()

output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
script = args.script.resolve()
sys.path.insert(0, str(script.parent))
os.environ["PATH"] = str(args.tools.resolve())
os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
sys.dont_write_bytecode = True
# CPython's generator uses one clang process per reported CPU. Limit this
# single Bazel action so it does not consume the entire host.
os.cpu_count = lambda: 4

# The upstream generator invokes clang once with cflags and again to assemble.
# Prevent both invocations from probing host GCC installations.
import _targets  # noqa: F401
import _llvm

_run_llvm = _llvm._run


async def _run_with_no_host_gcc(tool, arguments, echo=False):
    if tool == "clang":
        arguments = ["--gcc-toolchain=/dev/null", *arguments]
    return await _run_llvm(tool, arguments, echo=echo)


_llvm._run = _run_with_no_host_gcc
cflags = [
    "-nostdinc",
    "-isystem", str(args.glibc.resolve()),
    "-isystem", str(args.kernel.resolve()),
    "-isystem", str(args.resource.resolve() / "include"),
]
sys.argv = [
    str(script), args.target,
    "--output-dir", str(output),
    "--pyconfig-dir", str(args.pyconfig.resolve().parent),
    "--llvm-version", "22",
    "--cflags", shlex.join(cflags),
]
runpy.run_path(str(script), run_name="__main__")

# Give the platform-specific output a stable declared Bazel name and omit
# command comments containing execution-root paths.
platform_header = output / f"jit_stencils-{args.target}.h"
canonical_header = output / "jit_stencils_target.h"
content = platform_header.read_text()
# Its first comment is a regeneration digest containing absolute tool paths;
# Bazel tracks those inputs itself, so it does not belong in the output.
lines = [line for index, line in enumerate(content.split("\n")) if index != 0 and not line.startswith("// $ ")]
headers = json.loads(args.extra_headers.read_text())
if not isinstance(headers, list):
    raise ValueError("extra JIT headers must be a JSON array")
for header in reversed(headers):
    if not isinstance(header, str) or not re.fullmatch(r"[A-Za-z0-9_./-]+\.h", header) or ".." in header or header.startswith("/"):
        raise ValueError(f"invalid extra JIT header: {header!r}")
    lines.insert(0, f'#include "{header}"')
canonical_header.write_text("\n".join(lines))
platform_header.unlink()
entry_header = output / "jit_stencils.h"
content = entry_header.read_text().replace(platform_header.name, canonical_header.name)
entry_header.write_text("\n".join(line for line in content.split("\n") if not line.startswith("// $ ")))
