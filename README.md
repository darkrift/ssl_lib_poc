# `ssl_lib` BCR migration proof of concept

This Bazel 9.2 module exercises the modules named in the BCR discussion at
`bazelbuild/bazel-central-registry#9742`, plus `librdkafka`, after migrating
their direct OpenSSL/BoringSSL labels to the `@ssl_lib` facade from registry
commit `7d124815dfe1eb827d34b50b558d81401473297c`.

The registries are ordered in `.bazelrc`: the standard BCR is first and the
pinned raw GitHub registry is second. Consequently, normal modules use current
standard-BCR metadata while `ssl_lib@1.0.0` resolves from the pinned registry.
The checked-in module lockfile is enforced in error mode, so registry or module
extension changes cannot silently alter the resolved dependency graph.

## Checks

The default backend is BoringSSL, matching the pinned `ssl_lib` metadata:

```console
bazel build //examples:all_modules
```

The repository also supplies explicit OpenSSL and AWS-LC configurations, plus
a curl-specific Mbed TLS configuration:

```console
bazel build --config=openssl //examples:curl
bazel build --config=curl-mbedtls //examples:curl
bazel build --config=aws-lc //examples:curl
```

`curl-mbedtls` is deliberately not a repository-wide backend configuration.
Mbed TLS has a different C API, so the configuration is valid only for curl
and other targets that explicitly select native Mbed TLS sources.

The transition example analyzes and builds all four curl implementations in
one invocation, independently of the command-line default:

```console
bazel build //examples:curl_backend_matrix
```

`librdkafka` is intentionally wrapped in an OpenSSL `with_cfg` transition.
That transition also applies to its transitive curl dependency:

```console
bazel build //examples:librdkafka
```

A second librdkafka example keeps librdkafka's OpenSSL-only TLS source while a
nested transition selects Mbed TLS solely for its curl dependency:

```console
bazel build //examples:librdkafka_openssl_curl_mbedtls
```

The configured-graph analysis tests inspect transitive C++ headers and linker
inputs and require an exact expected set drawn from `boringssl`, `openssl`,
`aws-lc`, and `mbedtls`. In particular, this guards against BoringSSL leaking
into the OpenSSL-transitioned `librdkafka`/curl graph:

```console
bazel test //tests:ssl_graph_tests
```

The suite checks these ten invariants:

- `librdkafka` plus transitive curl: OpenSSL only
- Azure Core plus its curl transport: OpenSSL only
- FastDDS security: OpenSSL only
- Folly `AsyncSSLSocket`: OpenSSL only
- PPP EAP-TLS: OpenSSL only
- transitioned curl: BoringSSL only
- transitioned curl: OpenSSL only
- transitioned curl: AWS-LC only
- transitioned curl: Mbed TLS only
- mixed librdkafka/curl: exactly OpenSSL and Mbed TLS

## Module examples and patches

Every integrated SSL consumer has an independently buildable alias in
`//examples`. The table has one row per patch, including compatibility patches
against promoted transitive modules, so every root override is documented.

| Module | Version | Example or coverage | Patch | Change |
| --- | --- | --- | --- | --- |
| `asio` | `1.34.2.bcr.1` | `//examples:asio` | [`asio.patch`](patches/asio.patch) | Migrates the direct OpenSSL dependency and `:ssl` label to `ssl_lib`. |
| `aws_sdk` | `1.11.758` | `//examples:aws_sdk` | [`aws_sdk.patch`](patches/aws_sdk.patch) | Migrates the direct BoringSSL dependency and `:crypto` labels to `ssl_lib`. |
| `azure-core-cpp` | `1.14.1.bcr.2` | `//examples:azure-core-cpp` | [`azure-core-cpp.patch`](patches/azure-core-cpp.patch) | Migrates the direct OpenSSL dependency and curl transport labels to `ssl_lib`, retaining its API-mode selection. |
|  |  |  | [`azure-core-cpp-openssl4.patch`](patches/azure-core-cpp-openssl4.patch) | Makes issuer-name pointers const-correct for OpenSSL 4. |
| `boost.asio` | `1.90.0.bcr.1` | `//examples:boost.asio` | [`boost.asio.patch`](patches/boost.asio.patch) | Replaces the direct BoringSSL/OpenSSL dependencies and selected `:ssl` labels with `ssl_lib`. |
| `boost.mysql` | `1.90.0.bcr.1` | `//examples:boost.mysql` | [`boost.mysql.patch`](patches/boost.mysql.patch) | Replaces the direct BoringSSL/OpenSSL dependencies and selected `:crypto`/`:ssl` labels with `ssl_lib`. |
| `boost.mqtt5` | `1.90.0.bcr.1` | `//examples:boost.mqtt5` | [`boost.mqtt5.patch`](patches/boost.mqtt5.patch) | Migrates the direct OpenSSL dependency and both SSL API-mode label branches to `ssl_lib`. |
| `clickhouse-cpp` | `2.6.2` | `//examples:clickhouse-cpp` | [`clickhouse-cpp.patch`](patches/clickhouse-cpp.patch) | Replaces the direct BoringSSL/OpenSSL dependencies and selected `:crypto`/`:ssl` labels with `ssl_lib`. |
| `curl` | `8.21.0` | `//examples:curl` | [`curl.patch`](patches/curl.patch) | Replaces the direct BoringSSL/OpenSSL dependencies and backend-selected labels with `ssl_lib`. |
| `fastdds` | `3.4.2.bcr.1` | `//examples:fastdds` | [`fastdds.patch`](patches/fastdds.patch) | Migrates the direct OpenSSL dependency and repository-wide SSL target to the split `ssl_lib` facade. |
|  |  |  | [`fastdds-cxx20.patch`](patches/fastdds-cxx20.patch) | Replaces removed C++20 allocator members with `std::allocator_traits`. |
|  |  |  | [`fastdds-openssl4.patch`](patches/fastdds-openssl4.patch) | Makes subject-name pointers const-correct for OpenSSL 4. |
| `ffmpeg` | `7.1.1.bcr.beta.7` | `//examples:ffmpeg` | [`ffmpeg.patch`](patches/ffmpeg.patch) | Replaces the direct BoringSSL/OpenSSL dependencies and variant-selected labels with `ssl_lib`. |
| `folly` | `2026.05.18.00` | `//examples:folly` | [`folly.patch`](patches/folly.patch) | Migrates the direct OpenSSL dependency and portability `:crypto`/`:ssl` labels to `ssl_lib`. |
| `git` | `2.55.0` | `//examples:git` | [`git.patch`](patches/git.patch) | Migrates the direct OpenSSL dependency and SSL labels to `ssl_lib`. |
| `grpc` | `1.83.0` | `//examples:grpc` | [`grpc.patch`](patches/grpc.patch) | Replaces the direct BoringSSL/OpenSSL dependencies and backend aliases with `ssl_lib`. |
| `libevent` | `2.1.12-stable.bcr.0` | `//examples:libevent` | [`libevent.patch`](patches/libevent.patch) | Migrates the direct OpenSSL dependency and library, sample, and test labels to `ssl_lib`. |
| `libgit2` | `1.9.2.bcr.1` | `//examples:libgit2` | [`libgit2.patch`](patches/libgit2.patch) | Migrates the direct OpenSSL dependency and HTTPS `:ssl` labels to `ssl_lib`. |
| `librdkafka` | `2.15.0` | `//examples:librdkafka`<br>`//examples:librdkafka_openssl_curl_mbedtls` | [`librdkafka.patch`](patches/librdkafka.patch) | Migrates the direct OpenSSL dependency and TLS `:crypto`/`:ssl` labels to `ssl_lib`. |
|  |  |  | [`librdkafka-curl-mbedtls.patch`](patches/librdkafka-curl-mbedtls.patch) | Makes the curl dependency label-selectable and adds a nested transition target for curl's native Mbed TLS backend without changing librdkafka's OpenSSL backend. |
| `postgres` | `18.4` | `//examples:postgres` | [`postgres.patch`](patches/postgres.patch) | Replaces the direct BoringSSL/OpenSSL dependencies and selected labels with `ssl_lib`. |
| `ppp` | `2.5.2.bcr.1` | `//examples:ppp` | [`ppp.patch`](patches/ppp.patch) | Migrates the direct OpenSSL dependency and EAP-TLS `:crypto`/`:ssl` labels to `ssl_lib`. |
|  |  |  | [`ppp-hermetic-linux.patch`](patches/ppp-hermetic-linux.patch) | Fixes the Linux utmp timestamp assignment for a 64-bit `time_t` sysroot. |
| `rsync` | `3.4.2` | `//examples:rsync` | [`rsync.patch`](patches/rsync.patch) | Migrates the direct OpenSSL dependency and `:crypto` labels to `ssl_lib` and removes an OpenSSL-specific configure input. |
|  |  |  | [`rsync-llvm-linux.patch`](patches/rsync-llvm-linux.patch) | Supplies deterministic Linux configure results, removes host `cc` probing, and drops macOS-only inputs for Hermetic LLVM. |
| `double-conversion` | `3.3.1` | Transitive via `//examples:folly` | [`double-conversion-bazel9.patch`](patches/double-conversion-bazel9.patch) | Loads `cc_library` and `cc_test` explicitly from `rules_cc` for Bazel 9. |
| `foonathan_memory` | `0.7.3.bcr.2` | Transitive via `//examples:fastdds` | [`foonathan-memory-exec-tool.patch`](patches/foonathan-memory-exec-tool.patch) | Moves the generated-code helper into the genrule execution configuration so the host can run it. |
| `lz4` | `1.10.0.bcr.1` | Transitive via `//examples:rsync` | [`lz4-no-bundled-xxhash.patch`](patches/lz4-no-bundled-xxhash.patch) | Replaces bundled xxHash 0.6.5 sources and headers with BCR `xxhash@0.8.3.bcr.1`, preserving lz4's transitive link interface and fixing its frame and CLI targets without duplicate symbols. |
| `protobuf` | `35.1` | Transitive module metadata | [`protobuf-rust-dev-dependency.patch`](patches/protobuf-rust-dev-dependency.patch) | Marks Protobuf's lockfile-less Rust test crate extension as a development dependency for `rules_rust@0.72.0`. |

## Additional BCR candidates

The following modules are not yet integrated or patched in this repository.
Each entry is the latest non-yanked release in the standard BCR as of
2026-08-16 and declares a direct, non-development dependency on the listed SSL
implementation. No additional module directly depends on AWS-LC.

| Module | Version | SSL implementation | SSL version |
| --- | --- | --- | --- |
| `amqp-cpp` | `4.3.27` | OpenSSL | `3.5.5.bcr.4` |
| `azure-identity-cpp` | `1.10.1` | OpenSSL | `3.3.1.bcr.1` |
| `azure-storage-common-cpp` | `12.9.0` | OpenSSL | `3.3.1.bcr.1` |
| `capnp-cpp` | `1.4.0` | BoringSSL | `0.20241024.0` |
| `civetweb` | `1.16.bcr.4` | BoringSSL | `0.0.0-20230215-5c22014` |
| `com_github_mvukov_rules_ros2` | `0.0.0-20260718-352a8e3` | BoringSSL | `0.20251124.0` |
| `cpp-httplib` | `0.46.0` | BoringSSL | `0.20260327.0` |
| `distributed_point_functions` | `0.0.0` | BoringSSL | `0.20240930.0` |
| `fbthrift` | `2026.05.18.00` | OpenSSL | `3.5.5.bcr.0` |
| `fizz` | `2025.02.10.00.bcr.2` | OpenSSL | `3.3.1.bcr.9` |
| `foxglove_websocket` | `1.3.0` | BoringSSL | `0.20240913.0` |
| `foxglove_ws_protocol` | `0.8.1` | BoringSSL | `0.20251110.0` |
| `gazelle_orbit` | `0.3.0` | OpenSSL | `3.5.5.bcr.4` |
| `gloop` | `20260708.rc1` | BoringSSL | `0.20260413.0` |
| `google_cloud_cpp` | `3.8.0` | BoringSSL | `0.20251124.0` |
| `hiredis` | `1.3.0` | BoringSSL | `0.20250818.0` |
| `iperf` | `3.18.0` | OpenSSL | `3.3.1.bcr.1` |
| `jwt-cpp` | `0.7.0.bcr.1` | BoringSSL | `0.0.0-20240530-2db0eb3` |
| `jwt_verify_lib` | `0.0.0-20230517-b59e807` | BoringSSL | `0.0.0-20240530-2db0eb3` |
| `libssh2` | `1.11.1.bcr.1` | OpenSSL | `3.5.5.bcr.0` |
| `libwebsockets` | `4.5.2` | OpenSSL | `3.5.5.bcr.0` |
| `libzip` | `1.11.4.bcr.3` | BoringSSL | `0.20250514.0` |
| `linuxptp` | `4.4` | OpenSSL | `3.5.5.bcr.0` |
| `mosquitto` | `2.1.2.bcr.2` | OpenSSL | `3.5.5.bcr.3` |
| `open62541` | `1.4.17` | OpenSSL | `3.5.5.bcr.4` |
| `open62541pp` | `0.21.2` | OpenSSL | `3.5.5.bcr.4` |
| `opencensus-cpp` | `0.0.0-20230502-50eb5de.bcr.3` | BoringSSL | `0.20240913.0` |
| `openssh` | `9.9p1.bcr.2` | BoringSSL | `0.20241024.0` |
| `paho.mqtt.c` | `1.3.14.bcr.1` | BoringSSL | `0.20250311.0` |
| `prometheus-cpp` | `1.3.0.bcr.2` | BoringSSL | `0.0.0-20240530-2db0eb3` |
| `proxygen` | `2025.02.10.00.bcr.1` | OpenSSL | `3.5.4.bcr.0` |
| `qpdf` | `12.3.2` | OpenSSL | `3.3.1.bcr.0` |
| `rawrtc_re` | `0.6.0-3` | BoringSSL | `0.20251110.0` |
| `riegeli` | `0.0.0-20250822-9f2744d` | BoringSSL | `0.0.0-20240530-2db0eb3` |
| `rules_d` | `0.10.1` | BoringSSL | `0.20241209.0` |
| `s2geometry` | `0.14.0` | BoringSSL | `0.20260327.0` |
| `seastar` | `26.08.0-20260810180219-3bb2e379f54f` | OpenSSL | `3.5.5.bcr.4` |
| `tink_cc` | `2.9.1` | BoringSSL | `0.20260803.0` |
| `wangle` | `2025.02.10.00.bcr.2` | OpenSSL | `3.5.4.bcr.0` |
| `watchman` | `2026.07.06.00` | OpenSSL | `3.5.5.bcr.4` |
| `xilinx_bootgen` | `2025.2` | OpenSSL | `3.5.5.bcr.3` |

### Mbed TLS dependents and `ssl_lib` restrictions

Seven latest non-yanked BCR modules declare a direct runtime dependency on
Mbed TLS:

| Module | Version | Requested Mbed TLS version |
| --- | --- | --- |
| `curl` | `8.21.0` | `3.6.7` |
| `ffmpeg` | `7.1.1.bcr.beta.7` | `3.6.5` |
| `libarchive` | `3.8.1.bcr.2` | `3.6.0.bcr.1` |
| `libgit2` | `1.9.2.bcr.1` | `3.6.5` |
| `libssh2` | `1.11.1.bcr.1` | `3.6.5` |
| `mvfst` | `2025.01.20.00.bcr.1` | `3.6.0.bcr.1` |
| `zenoh-pico` | `1.8.0` | `3.6.5` |

At the pinned registry commit, [`ssl_lib@1.0.0`](https://github.com/jwnimmer-tri/bazel-central-registry/blob/7d124815dfe1eb827d34b50b558d81401473297c/modules/ssl_lib/1.0.0/overlay/BUILD.bazel)
is a label-level facade. It exposes `@ssl_lib//:crypto` and
`@ssl_lib//:ssl`, both defaulting to BoringSSL targets. It does not provide a
C/C++ API shim, translate headers or types, or select a consumer's
implementation-specific source files.

That distinction matters for Mbed TLS:

- OpenSSL, BoringSSL, and AWS-LC share enough of the OpenSSL API shape for many
  consumers to compile the same source mode, although individual compatibility
  differences still require testing and sometimes patches.
- Mbed TLS uses its own `mbedtls/...` headers, types, and functions. Redirecting
  an OpenSSL-coded target to Mbed TLS through a label flag cannot make that
  source compatible.
- The BCR's [`mbedtls@3.6.7`](https://github.com/bazelbuild/bazel-central-registry/blob/main/modules/mbedtls/3.6.7/overlay/BUILD.bazel)
  exposes one monolithic `@mbedtls//:mbedtls` target rather than separate
  `:crypto` and `:ssl` targets. Both facade flags can technically select that
  same target, but only for a consumer that already has a native Mbed TLS code
  path.
- A complete Mbed TLS transition must therefore set both the facade labels and
  the consumer's API-mode flag. Examples include curl's `ssl_lib=mbedtls`,
  FFmpeg's `enable_mbedtls=True`, libgit2's `use_https=mbedtls`, and libssh2's
  `crypto_backend=mbedtls` settings.
- Consumers without a native Mbed TLS implementation require an upstream code
  port or adapter; an `ssl_lib` migration patch alone is insufficient.

The curl example now exercises both its migrated OpenSSL branch and its native
direct `@mbedtls` branch. Both `ssl_lib` labels select the monolithic Mbed TLS
target in that configuration for consistency, but curl's `ssl_lib=mbedtls`
source-mode setting is what makes the code compatible. FFmpeg and libgit2 still
leave their native `@mbedtls` branches direct and are not included in the Mbed
TLS example. The configured graph checker recognizes Mbed TLS and verifies both
the curl-only graph and the intentionally mixed librdkafka/curl graph.

The discussion's `awk_sdk` is treated as a typo for the BCR module `aws_sdk`.
The yanked former `clickhouse-cpp-client` entry is represented by its current
module name, `clickhouse-cpp`. WolfSSL is not in the standard BCR, so AWS-LC is
the third backend; curl supports its BoringSSL-compatible API. `librdkafka`
remains OpenSSL-only because its TLS source uses OpenSSL-specific APIs.
Azure Core's curl transport similarly uses OpenSSL OCSP APIs, so that example
has its own OpenSSL transition while the repository default remains BoringSSL.
Its second patch is a four-line const-correctness update required by OpenSSL 4's
`X509_get_issuer_name` and `X509_CRL_get_issuer` declarations.

## Hermetic toolchains and promoted dependencies

Hermetic Build's `llvm@0.8.14` is always registered and the build platform is
fixed through a main-repository alias to its zero-sysroot
`linux_x86_64_gnu.2.28` target. The local alias also lets IDE `bazel info`
commands parse the platform flag before Bzlmod repository mappings exist.
Platform-specific
`.bazelrc` discovery is disabled, strict action/repository environments are
enabled, Java uses downloaded Remote JDK 21 runtimes, and sandboxed actions may
not use the network.

Several transitive modules are deliberately promoted in `MODULE.bazel`:

- `rules_rust@0.72.0` avoids carrying a rules_rust patch.
- `with_cfg.bzl@1.0.0` supersedes LLVM's older compatible request and provides
  the direct per-target transitions.
- `protobuf@35.1` stays current, with a separate metadata patch marking its
  lockfile-less Rust test crate extension development-only for rules_rust 0.72.
- the current `envoy_api` revision avoids gRPC's older retired `googleapis`
  extension import.
- `c-ares@1.34.6` replaces gRPC's `1.19.1`, whose global `cc_library` use was
  removed by Bazel 9.
- `glog@0.7.1.bcr.1` replaces Folly's `0.7.1`; the BCR metadata revision fixes
  its removed `native.cc_library` call.
- `libunwind@1.8.3` replaces Folly's `1.8.1`, whose BUILD file uses the removed
  global `cc_test` symbol.
- `libdwarf@2.2.0.bcr.1` replaces Folly's `0.12.0.bcr.1`, whose test macro calls
  the removed `native.cc_test`.
- `double-conversion@3.3.1` is already the newest BCR release, so a separate
  compatibility patch adds its missing Bazel 9 `rules_cc` loads.
- `lz4@1.10.0.bcr.1` is also current; a separate patch replaces its bundled
  xxHash 0.6.5 implementation and header with `xxhash@0.8.3.bcr.1`. Both lz4
  and rsync consequently resolve to one standalone xxhash library while
  lz4's frame and CLI targets retain the include and link interface they need.
- `foonathan_memory@0.7.3.bcr.2` is current; its helper is moved from a
  genrule's target-configured `srcs` to its exec-configured `tools`, preventing
  a cross-compiled Linux generator from being executed on macOS.
- `rules_cc@0.2.22` is made directly visible because Bazel 9 requires graph
  tests to import `CcInfo` from rules_cc rather than using a global symbol.

The platform-independent test toolchain in `//toolchains` contains no compiler
or host tool. It only lets Bazel execute the generated analysis-test pass/fail
stub on the host while compiled code remains on the fixed LLVM Linux platform.

Rsync has a second patch specifically for this toolchain: the BCR overlay ships
a macOS-generated `config.h` and compiles a configure probe with local `cc`.
The patch supplies the fixed Linux x86-64 results, removes macOS-only headers
and `-liconv`, and makes `rounding.h` deterministic without invoking a host C
compiler. ACL/xattr support is disabled in this smoke build because the overlay
does not run target-aware feature probes.

FastDDS has a second patch replacing the `std::allocator::construct/destroy`
members removed in C++20 with `std::allocator_traits`; its foonathan-memory
generator is separately patched into the LLVM execution configuration. A third
patch applies OpenSSL 4's const-correct `X509_NAME` API. Its security sources
use OpenSSL-only headers, so the example has an OpenSSL transition while the
command-line default remains BoringSSL.

PPP has a separate hermetic-Linux patch for its utmp timestamp assignment. The
LLVM sysroot correctly exposes 64-bit `time_t`, while Linux's utmp field remains
32-bit, so passing the field to `time()` is not type-safe.
