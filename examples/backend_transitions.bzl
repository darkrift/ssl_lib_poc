"""Transitioned smoke rules for selecting an ssl_lib implementation per target."""

load("@with_cfg.bzl", "with_cfg")

def _ssl_backend_filegroup(crypto, ssl, api_mode):
    builder = with_cfg(native.filegroup)

    # ssl_lib's actual facade targets.
    builder.set(Label("@ssl_lib//:crypto"), Label(crypto))
    builder.set(Label("@ssl_lib//:ssl"), Label(ssl))

    # Source-level API switches retained by patched consumers. AWS-LC uses the
    # BoringSSL API mode while providing different facade targets.
    builder.set(Label("@boost.asio//:ssl"), api_mode)
    builder.set(Label("@boost.mysql//:ssl"), api_mode)
    builder.set(Label("@boost.mqtt5//:ssl"), api_mode)
    builder.set(Label("@clickhouse-cpp//:tls"), api_mode)
    builder.set(Label("@curl//:ssl_lib"), api_mode)
    builder.set(Label("@ffmpeg//:enable_boringssl"), api_mode == "boringssl")
    builder.set(Label("@ffmpeg//:enable_openssl"), api_mode == "openssl")
    builder.set(Label("@grpc//third_party:grpc_use_openssl"), api_mode == "openssl")
    builder.set(Label("@libgit2//:use_https"), "openssl")
    builder.set(Label("@postgres//:with_ssl"), api_mode)

    return builder.build()

boringssl_filegroup, _boringssl_filegroup_internal = _ssl_backend_filegroup(
    crypto = "@boringssl//:crypto",
    ssl = "@boringssl//:ssl",
    api_mode = "boringssl",
)

openssl_filegroup, _openssl_filegroup_internal = _ssl_backend_filegroup(
    crypto = "@openssl//:crypto",
    ssl = "@openssl//:ssl",
    api_mode = "openssl",
)

aws_lc_filegroup, _aws_lc_filegroup_internal = _ssl_backend_filegroup(
    crypto = "@aws-lc//:crypto",
    ssl = "@aws-lc//:ssl",
    api_mode = "boringssl",
)

# Unlike the OpenSSL-compatible implementations above, curl must select its
# dedicated Mbed TLS sources. The BCR Mbed TLS module exposes one monolithic
# target, so both facade labels intentionally select the same library.
_curl_mbedtls_builder = with_cfg(native.filegroup)
_curl_mbedtls_builder.set(Label("@ssl_lib//:crypto"), Label("@mbedtls//:mbedtls"))
_curl_mbedtls_builder.set(Label("@ssl_lib//:ssl"), Label("@mbedtls//:mbedtls"))
_curl_mbedtls_builder.set(Label("@curl//:ssl_lib"), "mbedtls")
curl_mbedtls_filegroup, _curl_mbedtls_filegroup_internal = _curl_mbedtls_builder.build()

# Keep librdkafka's own OpenSSL-only TLS implementation in the parent
# configuration, but select the dependency-edge wrapper added by its second
# patch. That wrapper applies a nested Mbed TLS transition only to curl.
_librdkafka_mixed_builder = with_cfg(native.filegroup)
_librdkafka_mixed_builder.set(Label("@ssl_lib//:crypto"), Label("@openssl//:crypto"))
_librdkafka_mixed_builder.set(Label("@ssl_lib//:ssl"), Label("@openssl//:ssl"))
_librdkafka_mixed_builder.set(Label("@curl//:ssl_lib"), "openssl")
_librdkafka_mixed_builder.set(
    Label("@librdkafka//:curl_dependency"),
    Label("@librdkafka//:curl_mbedtls"),
)
librdkafka_openssl_curl_mbedtls_filegroup, _librdkafka_mixed_filegroup_internal = _librdkafka_mixed_builder.build()
