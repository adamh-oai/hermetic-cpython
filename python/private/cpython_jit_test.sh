#!/usr/bin/env bash
set -euo pipefail

# --- begin runfiles.bash initialization v3 ---
set +e
runfiles_library=bazel_tools/tools/bash/runfiles/runfiles.bash
# shellcheck disable=SC1090
source "${RUNFILES_DIR:-/dev/null}/$runfiles_library" 2>/dev/null || \
  source "$(grep -sm1 "^$runfiles_library " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null || \
  source "$0.runfiles/$runfiles_library" 2>/dev/null || \
  source "$(grep -sm1 "^$runfiles_library " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  source "$(grep -sm1 "^$runfiles_library " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  { echo "cannot find $runfiles_library" >&2; exit 1; }
unset runfiles_library
set -e
# --- end runfiles.bash initialization v3 ---

python="$(rlocation "$1")"
readonly python

PYTHON_JIT=1 "$python" -c '
import _opcode
import sys

assert sys._jit.is_available() and sys._jit.is_enabled()

def hot_loop():
    total = 0
    for i in range(100_000):
        total += i
    return total

assert hot_loop() == 4_999_950_000
executors = []
for offset in range(0, len(hot_loop.__code__.co_code), 2):
    try:
        executor = _opcode.get_executor(hot_loop.__code__, offset)
    except ValueError:
        continue
    if executor is not None:
        executors.append(executor)
assert executors, "hot loop did not create an executor"
assert any(executor.get_jit_code() for executor in executors), "executor has no JIT code"
'

PYTHON_JIT=1 "$python" -m unittest test.test_sys.TestSysJIT
