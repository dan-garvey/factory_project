# Native Git tree metadata validation

This component validates a captured, NUL-delimited `git ls-tree -rz --full-tree`
listing before a future native staged exporter consumes it. It is not the
installed gate and does not authenticate the listing, read any blob, check the
current index, execute Git, discover tests or invoke a compiler. Those remain
the native coordinator's responsibility in `factory-yau.3.17.4`. Existing
mandatory gates stay active.

The library accepts exact regular/executable blob records with explicitly
selected SHA-1 or SHA-256 object widths. Its validated manifest has no public
constructor or mutable entry accessor. Duplicate paths, file/directory
collisions, absolute/traversing/noncanonical paths, `.git` and `.beads` path
components, backslashes, drive prefixes and invalid UTF-8 refuse before a
passing manifest can be emitted. Quoted and control bytes in valid path names
are encoded unambiguously in JSON.

These are deliberate build-adapter bounds: 2 MiB of raw metadata, 4096 records,
4096 bytes per path and 4 MiB of JSON output including its final newline.
Symlinks and submodules are unsupported. The parser is stricter than the
current Python starter for malformed framing, nested private paths and
non-UTF-8 names; it does not claim complete gate parity or impose game rules.
An empty tree is valid metadata but cannot by itself satisfy a source gate.

Use the pinned Bazel and original admission described in
[native builds](../../docs/engineering/native-builds.md). Targets are
`//native/validation:tree_manifest_tests` and
`//native/validation:tree_manifest_cli`. The CLI reads only standard input:

```text
tree_manifest_cli --object-format sha1 < captured-tree.raw
```

Capture the full actual Git command, tree identity and raw-input digest
separately. A syntactically valid invented listing is not proof that Git
produced it. A caller must require original exit zero and a complete passing
JSON document, retain failures and bound the process lifetime. The CLI buffers
the entire validated JSON before writing; it cannot make a pipe write atomic
if the consumer disconnects or output fails. Such an I/O failure is nonzero.

The library and CLI own no filesystem mutation, subprocess, quantity state,
private tracker access or admission policy. Its invented tests exercise the
metadata boundary only. No game, GDScript parser, world restoration or user
play is established by this component.

The raw record format and verbatim NUL termination follow the
[Git ls-tree documentation](https://git-scm.com/docs/git-ls-tree).
