# Godot C API value boundary

This package converts owned portable values to engine Variants and back. The
native World bridge is its only external Bazel consumer; local table checks and
the ABI fixture remain support targets in this package. The bridge uses it for
commands, projections and typed checkpoints.
It contains no quantity owner, command cache, mutable world or fallback authority.
The offline bridge and shared Session have separate adoption scopes.

The supported values are null, boolean, signed 64-bit integer, finite double,
UTF-8 String, ordered Array and String-keyed Dictionary. Import checks the actual
Variant kind before reading it. Integer and boolean values never pass through
floating point or JSON. Returned portable containers own their data; exported
engine containers are newly constructed. Other engine types and dictionary key
kinds are refused, without coercion.

The adapter currently requires the exact recorded engine revision and a 64-bit
host. Its reversible string profile rejects embedded null bytes and invalid
UTF-8. A string is limited to 1 MiB, all strings together to 4 MiB, nesting to 32
and value nodes to 100,000. These are adapter limits, not permanent game rules.
Native strings are checked as Unicode scalars before encoding. Newly created
engine strings must encode back to the exact input bytes; decoder normalization
is refused rather than silently changing an identifier or historical value.
Array export asks the engine to resize once, checks its returned error code,
then writes each child through the pinned indexed Variant setter and checks
validity and bounds. The adapter still constructs a fresh engine Array for
each plain Array and retains the same node, depth and string limits.
The portable value type itself retains byte-exact strings. A future state importer
must explicitly refuse an unsupported checkpoint rather than reset or normalize it.

`NativeValue` owns one initialized engine Variant. Moving transfers ownership,
and destruction calls the engine destructor exactly once. Temporary Strings,
StringNames, return values and partially constructed containers are also owned.
Destroy every engine value while the host engine is still alive. Calls must run
synchronously on the owning engine thread; mutating an input concurrently is
outside this boundary. No engine object is retained in the portable value layer.

The C API uses opaque aligned storage. The exported size table records at most
40 bytes for the supported 64-bit Variant configurations, and 8 bytes for String
and StringName. Each engine operation receives one pointer; these storage sizes
are never used to walk an engine array. Required function pointers, scalar
constructors and destructors must all exist before conversion is available.

The vendored header is the unmodified MIT-licensed output of the already verified
engine. It retains its original notice. Its source revision and SHA-256 are in
[vendor/PROVENANCE.md](vendor/PROVENANCE.md). A header export proves metadata
provenance, not successful conversion or extension loading.

## Build and verify

Use `//native/factory-godot-values:godot_values`, `:api_table_test` and
`:factory-value-abi-fixture.so` through [native builds](../../docs/engineering/native-builds.md).
The table test uses invented API tables; exercise the actual engine ABI separately.
Keep dated outcomes and current adoption work in Beads.
