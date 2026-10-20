# Typed values for the native authority boundary

This engine-independent C++20 library supports the logical World in
`factory-yau.3.17.7`. It is not yet connected to the live Model, Session or Store.
It adds no JSON parser, state owner, engine dependency or downloaded package.

`Value` owns null, boolean, signed 64-bit integer, finite double, byte-exact string,
ordered array or string-keyed dictionary data. It does not promote integers into
floating point. Container access is read only, and constructing from a builder
copies or moves its owned data rather than borrowing an engine container. The
future adapter must validate schema, string encoding and input quotas before
admission; this type layer does not grant authority to an identifier or quantity.

`typed_difference` retains scalar types and should be used for native authority,
historical command and checkpoint comparisons after schema validation.
`wire_difference` is a separate observation-only operation: it permits exact finite
integer/float equivalence but keeps booleans, strings, null, dictionary keys, array
length and array order distinct. It uses no epsilon and does not round an integer
to double before comparison. Neither function converts or mutates either input.

Both functions return the first differing path and reason, or no difference.
Dictionary traversal uses stable sorted keys; a path escapes quotes, backslashes
and control bytes. Diagnostics identify the field and types without copying its
contents. Both comparisons refuse beyond the declared depth, which defaults to 32.
The caller must retain the complete initial observation before asserting and must
not publish a validated-ready marker merely because a raw observation was written.

Use `//native/factory-value:value` and `//native/factory-value:value_test` through
the canonical [Bazel build](../../docs/engineering/native-builds.md), with owned
external outputs and ordinary resource admission. Retained CMake files describe
the historical component fixture, not a competing default build system. Changes
use relevant automated tests and one independent reviewer, reusing passing work
for unchanged inputs.

Native tests distinguish strict and observation comparisons, integer boundaries,
one-unit changes above the exact-double integer range, nearby floating-point
values, booleans, keys, ordered arrays, nested diagnostics and depth refusal. They
do not prove a JSON decoder, engine ABI, native extension load, checkpoint import,
request replay or actual gameplay. Existing mandatory gates remain unchanged.
