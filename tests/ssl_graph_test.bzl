"""Analysis tests that enforce one SSL implementation per configured graph."""

load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

SslImplementationsInfo = provider(
    doc = "SSL implementation repositories reachable from a configured target.",
    fields = {
        "implementations": "A depset containing recognized SSL implementations.",
    },
)

_IMPLEMENTATION_MODULES = [
    "aws-lc",
    "boringssl",
    "mbedtls",
    "openssl",
]

def _implementation_for_label(label):
    """Returns the SSL implementation owning label, if it is one we track."""
    repository = label.workspace_name
    for implementation in _IMPLEMENTATION_MODULES:
        # workspace_name is the canonical Bzlmod repository name in configured
        # targets (for example, "openssl+"). Accept apparent names as well so
        # the rule also works if the repositories are supplied outside Bzlmod.
        if repository == implementation:
            return implementation
        if repository.startswith(implementation + "+"):
            return implementation
        if repository.startswith(implementation + "~"):
            return implementation
    return None

def _record_implementation(label, implementations):
    if label:
        implementation = _implementation_for_label(label)
        if implementation:
            implementations.append(implementation)

def _collect_target(target, transitive):
    if type(target) == "Target" and SslImplementationsInfo in target:
        transitive.append(target[SslImplementationsInfo].implementations)

def _ssl_implementations_aspect_impl(target, ctx):
    direct = []
    transitive = []

    _record_implementation(target.label, direct)

    # CcInfo contains the transitive compile and link graph of a C/C++ target.
    # Reading it at the first provider-forwarding alias avoids walking every
    # source/configuration/toolchain node inside large SSL implementations.
    if CcInfo in target:
        cc_info = target[CcInfo]
        for linker_input in cc_info.linking_context.linker_inputs.to_list():
            _record_implementation(linker_input.owner, direct)
        for header in cc_info.compilation_context.headers.to_list():
            _record_implementation(header.owner, direct)

    if ctx.rule:
        # These are the provider-forwarding edges used by alias, filegroup, and
        # with_cfg's transitioning alias. They lead to the CcInfo-bearing root
        # without pulling compiler, test-runner, or other toolchain internals
        # into the graph under test.
        for attribute_name in ["actual", "exports", "srcs"]:
            if not hasattr(ctx.rule.attr, attribute_name):
                continue
            value = getattr(ctx.rule.attr, attribute_name)
            if type(value) == "Target":
                _collect_target(value, transitive)
            elif type(value) == "list" or type(value) == "tuple":
                for item in value:
                    _collect_target(item, transitive)

    return [
        SslImplementationsInfo(
            implementations = depset(
                direct = direct,
                transitive = transitive,
            ),
        ),
    ]

_ssl_implementations_aspect = aspect(
    implementation = _ssl_implementations_aspect_impl,
    attr_aspects = ["actual", "exports", "srcs"],
    doc = "Collects SSL implementation repositories from a configured graph.",
)

def _ssl_implementations_test_impl(ctx):
    found = sorted(
        ctx.attr.target[SslImplementationsInfo].implementations.to_list(),
    )
    expected = sorted(ctx.attr.expected)
    success = found == expected

    if success:
        message = "%s uses exactly %s" % (ctx.attr.target.label, expected)
    else:
        message = "%s must use exactly %s; found %s" % (
            ctx.attr.target.label,
            expected,
            found,
        )

    return [AnalysisTestResultInfo(success = success, message = message)]

ssl_implementations_test = rule(
    implementation = _ssl_implementations_test_impl,
    attrs = {
        "expected": attr.string_list(
            mandatory = True,
        ),
        "target": attr.label(
            mandatory = True,
            aspects = [_ssl_implementations_aspect],
        ),
    },
    analysis_test = True,
    doc = "Fails unless a configured target graph contains exactly the expected SSL implementations.",
)

def single_ssl_implementation_test(name, target, expected, **kwargs):
    """Declares the common exact-singleton form of ssl_implementations_test."""
    ssl_implementations_test(
        name = name,
        expected = [expected],
        target = target,
        **kwargs
    )
