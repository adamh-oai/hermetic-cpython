"""Bzlmod extension for selecting CPython source releases."""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("//python/private:repositories.bzl", "cpython_source_repository")
load("//python/private:versions.bzl", "CPYTHON_RELEASES")

_BUILD_FILE = Label("//:cpython.BUILD.bazel")
_LIBFFI_BUILD_FILE = Label("//:libffi.BUILD.bazel")
_ZSTD_BUILD_FILE = Label("//:zstd.BUILD.bazel")
_JIT_LLVM_BUILD_FILE = Label("//python/private:jit_llvm.BUILD.bazel")

# CPython 3.15's JIT generator uses LLVM 22. These are host tools for
# generating stencils, independent of the LLVM toolchain that builds Python.
_JIT_LLVM_ARCHIVES = {
    "linux_amd64": "379f4a009e873c7dc0a9ef2593dab44d3da48ee5c4f05db1382f8cd18779d26d",
    "linux_arm64": "9ddfbca0cd3fdb90b5c8d6bd35729d4769aca39659892ad5e1b1fb83dd272634",
}

def _python_impl(module_ctx):
    requested_versions = {}
    root_requested_versions = {}
    sources = {}

    for module in module_ctx.modules:
        for version_tag in module.tags.version:
            version = version_tag.version
            if version not in CPYTHON_RELEASES:
                fail(
                    "Unsupported Python version {version!r}; supported versions are {supported}".format(
                        version = version,
                        supported = ", ".join(sorted(CPYTHON_RELEASES.keys())),
                    ),
                )

            requested_versions[version] = True
            if module.is_root:
                root_requested_versions[version] = True

        for source_tag in module.tags.source:
            if not module.is_root:
                fail("Only the root module may select a CPython source archive")
            if source_tag.version != "3.15":
                fail("Custom source archives are currently supported only for CPython 3.15")
            if source_tag.version in sources:
                fail("CPython {} has more than one source archive".format(source_tag.version))
            if not source_tag.urls or len(source_tag.sha256) != 64 or any([
                c not in "0123456789abcdef"
                for c in source_tag.sha256.elems()
            ]):
                fail("A custom CPython source requires URLs and a lowercase SHA-256")
            sources[source_tag.version] = source_tag

    for version in sources:
        if version not in root_requested_versions:
            fail("A CPython source archive must have a matching root version tag")

    # CPython 3.15's JIT stencil generator runs with a separate host Python.
    # Make that interpreter available even when consumers only request 3.15.
    if "3.15" in requested_versions:
        requested_versions["3.14"] = True

    if requested_versions:
        # Declare both repositories alongside the Python repositories so their
        # labels resolve even when a consumer selects an older Python version.
        # Bazel only downloads the archive used by a JIT build.
        for platform, sha256 in _JIT_LLVM_ARCHIVES.items():
            http_archive(
                name = "cpython_jit_llvm_" + platform,
                build_file = _JIT_LLVM_BUILD_FILE,
                sha256 = sha256,
                urls = ["https://github.com/hermeticbuild/hermetic-llvm/releases/download/llvm-22.1.4-1/llvm-toolchain-minimal-22.1.4-{}-musl.tar.zst".format(platform.replace("_", "-"))],
            )

        http_archive(
            name = "cpython_libffi",
            build_file = _LIBFFI_BUILD_FILE,
            integrity = "sha256-E4YH3uJovezzdK35FEwA6DnjhUH3XySh/PGLeP2kiy0=",
            patch_args = ["-p1"],
            patches = [
                Label("//python/patches/libffi:clang-cl-aarch64-hfa.patch"),
                Label("//python/patches/libffi:windows-arm64-seh.patch"),
            ],
            strip_prefix = "libffi-3.4.7",
            urls = ["https://github.com/libffi/libffi/releases/download/v3.4.7/libffi-3.4.7.tar.gz"],
        )

        # Keep the Zstandard source and notices independent of the consumer's
        # selected module versions and repository overrides.
        http_archive(
            name = "cpython_zstd",
            build_file = _ZSTD_BUILD_FILE,
            integrity = "sha256-6zPlH0mhXgI5UM14Jcp0pKK0Pbg1SCWsJPwbfuCeb6M=",
            strip_prefix = "zstd-1.5.7",
            urls = ["https://github.com/facebook/zstd/releases/download/v1.5.7/zstd-1.5.7.tar.gz"],
        )

    for version in sorted(requested_versions.keys()):
        release = CPYTHON_RELEASES[version]
        repository_name = release.repository_name
        source = sources.get(version)
        cpython_source_repository(
            name = repository_name,
            build_file = _BUILD_FILE,
            build_details_schema = release.build_details_schema or "",
            cache_tag = release.cache_tag,
            hexversion = release.hexversion,
            major = release.major,
            micro = release.micro,
            minor = release.minor,
            minor_version = release.minor_version,
            needs_deepfreeze = release.needs_deepfreeze,
            patches = release.patches,
            release = release.release,
            release_level = release.release_level,
            resource_field3 = release.resource_field3,
            serial = release.serial,
            sha256 = source.sha256 if source else release.sha256,
            soabi = release.soabi,
            strip_prefix = source.strip_prefix if source else release.strip_prefix,
            supports_isolated_interpreters = release.supports_isolated_interpreters or False,
            urls = source.urls if source else release.urls,
            venv_launcher_kind = release.venv_launcher_kind,
            venv_launcher_runtime_name = release.venv_launcher_runtime_name,
            venv_launcher_source = release.venv_launcher_source,
            venvw_launcher_runtime_name = release.venvw_launcher_runtime_name,
            windows_pyconfig_template = release.windows_pyconfig_template,
            pinned_source = source != None,
            extra_frozen_modules_json = source.extra_frozen_modules_json if source else "{}",
            jit_extra_headers = source.jit_extra_headers if source else [],
            module_copts_json = source.module_copts_json if source else "{}",
        )

    root_direct_deps = [
        CPYTHON_RELEASES[version].repository_name
        for version in sorted(root_requested_versions.keys())
    ]
    root_direct_dev_deps = []
    if not module_ctx.root_module_has_non_dev_dependency:
        root_direct_dev_deps = root_direct_deps
        root_direct_deps = []

    return module_ctx.extension_metadata(
        reproducible = True,
        root_module_direct_deps = root_direct_deps,
        root_module_direct_dev_deps = root_direct_dev_deps,
    )

_version = tag_class(
    attrs = {
        "version": attr.string(mandatory = True),
    },
    doc = "Selects a supported Python minor version.",
)

_source = tag_class(
    attrs = {
        "version": attr.string(mandatory = True),
        "urls": attr.string_list(mandatory = True),
        "sha256": attr.string(mandatory = True),
        "strip_prefix": attr.string(),
        "extra_frozen_modules_json": attr.string(default = "{}"),
        "jit_extra_headers": attr.string_list(),
        "module_copts_json": attr.string(default = "{}"),
    },
    doc = "Selects a checksum-pinned source archive and its additional build inputs.",
)

python = module_extension(
    implementation = _python_impl,
    tag_classes = {
        "source": _source,
        "version": _version,
    },
)
