# CPython for Bazel

This module builds selected CPython releases from source and exposes each
selected interpreter as a Bazel repository. The public API uses a CPython
minor version such as `3.13`; the generated repository name replaces the dot
with an underscore, such as `python3_13`.

## Project goal

This project is reproducing the standalone CPython distributions provided by
[python-build-standalone](https://github.com/astral-sh/python-build-standalone)
with hermetic Bazel builds. The build uses official CPython source archives,
target-toolchain checks, and declared Bazel actions; it does not run CPython's
`configure` script or `make`.

The distribution layout and metadata are still being aligned with
python-build-standalone. The current `@python3_XX//:python` targets are complete
build and test runtimes, but they are not yet a compatibility guarantee for
every python-build-standalone archive path or metadata file.

## Select CPython versions

Add the module and select each required CPython version in `MODULE.bazel`:

```starlark
bazel_dep(name = "cpython", version = "<module version>")

python = use_extension("@cpython//python:extensions.bzl", "python")
python.version(version = "3.14")
python.version(version = "3.13")
python.version(version = "3.12")
python.version(version = "3.11")
use_repo(
    python,
    "python3_14",
    "python3_13",
    "python3_12",
    "python3_11",
)
```

The selected interpreters are addressed by their generated repository names:

```starlark
alias(
    name = "python_3_13",
    actual = "@python3_13//:python",
)

alias(
    name = "python_3_12",
    actual = "@python3_12//:python",
)
```

The supported CPython minor versions are 3.11, 3.12, 3.13, and 3.14. Each
`python.version` call selects one CPython minor version. A consumer must also
list the corresponding generated repository in `use_repo` before referring to
it from a label.

## Experimental CPython 3.15 source builds

Version `3.15` builds a pinned 3.15.0a5 release by default. It also accepts a
user-provided source snapshot. Select it with `python.version(version = "3.15")`
and set
`--repo_env=CPYTHON_3_15_SOURCE_ARCHIVE=/absolute/path/to/source.tar.gz`.
The archive must have the CPython source files at its root. The build checks
the source's major and minor version and derives its full release metadata
from `Include/patchlevel.h`.

Custom source trees can request additional frozen modules using
`--repo_env=CPYTHON_3_15_EXTRA_FROZEN_MODULES=<json>`, where the JSON object maps
an output path under `Python/frozen_modules/` to a two-element array of the
module name and source path. For example,
`{"Python/frozen_modules/example.h":["example","Lib/example.py"]}`.
The default is an empty object. Pass the JSON as a single shell argument.

On Linux x86-64 and AArch64 the 3.15 build enables the experimental JIT. Set
`--@python3_15//:cpython_jit=false` to disable it. Custom source trees may set
`CPYTHON_3_15_JIT_EXTRA_HEADERS` to a JSON array of header names to include in
generated stencils, and `CPYTHON_3_15_MODULE_COPTS` to a JSON object mapping
module names to additional compiler-flag arrays. Pass both as Bazel
`--repo_env` values; the defaults are empty.

The LLVM toolchains build each selected CPython release for Linux, macOS, and
Windows on arm64 and x86_64. Windows targets use the MSVC ABI, the hermetic MSVC
runtime, and the hermetic Windows SDK supplied by `windows_support`.

## Integration fixture

[`tests/integration`](tests/integration) is a nested Bzlmod consumer. It selects
all four supported minor versions and defines smoke tests for the reported
Python version, standard-library and encoding imports, compiled-module imports,
and starting a child interpreter with `subprocess`.

## Configure check audit

[`tools/configure_checklist.py`](tools/configure_checklist.py) reads the pinned
`configure.ac` files, `pyconfig.h.in` files, generated `pyconfig.h` files, and
`rules_cc_autoconf` manifests. It does not execute `configure`. The generated
[`docs/configure-check-audit.md`](docs/configure-check-audit.md) records every
CPython 3.11, 3.12, 3.13, and 3.14 template symbol for Linux arm64, Linux
x86_64, Darwin arm64, and Darwin x86_64. A probe classification requires a
`rules_cc_autoconf` producer in every generated configuration where the symbol
exists. The classifications and configure decisions that do not emit template
symbols are stored in
[`tools/configure_check_dispositions.json`](tools/configure_check_dispositions.json).

Run `tools/configure_check_audit.sh` to rebuild all 16 generated configurations
and update the audit. CI runs `tools/configure_check_audit.sh --check`. The
`--require-classified` check requires the complete 16-configuration matrix,
validates reviewed expected values, and requires every new template symbol to
have a `rules_cc_autoconf` producer or an explicit reviewed disposition.
