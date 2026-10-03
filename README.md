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

The JIT generator runs using a separate host CPython 3.14 and pinned LLVM
22.1.4 tools and Clang headers. The interpreter itself uses the pinned LLVM
22 toolchain. The upstream generator warns that LLVM versions other than 21
are unsupported. JIT builds require a Linux x86-64 or AArch64 execution host;
the generator selects its tools for the execution architecture. Selecting 3.15
automatically creates the 3.14 repository for this internal dependency; it
does not need a separate `use_repo` entry.

### Using the fork as a dependency

Bzlmod applies module overrides only from the root module. When using this
fork from another workspace, copy the `python/patches` directory from the
same fork revision into the root workspace and copy the `single_version_override`
and `archive_override` declarations from this fork's `MODULE.bazel` into the
root `MODULE.bazel`. The patch labels in those declarations refer to the
copied files. In particular, the pinned LLVM override and its JIT and PGO
patches are required for the corresponding features. Add a root
`bazel_dep(name = "llvm", version = "0.8.8")` and configure the toolchain
with `--extra_toolchains=@llvm//toolchain:all`; the remaining local toolchain
settings can be copied from this repository's `.bazelrc`.

On POSIX platforms the runtime includes a shared libpython next to the Python
executable. On Linux the pinned LLVM toolchain also supplies the profiling
runtime and accepts Bazel's `--fdo_optimize` for an LLVM profile; producing
the training profile and choosing a workload are the consumer's responsibility.

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
