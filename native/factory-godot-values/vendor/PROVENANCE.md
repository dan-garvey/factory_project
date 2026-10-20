# Engine interface provenance

`gdextension_interface.h` is copied without edits from the first actual API export
of the existing verified Godot runtime. Its original MIT notice remains in the
header.

| Field | Exact identifier |
| --- | --- |
| Engine source commit | `ed1daf0bf001b61586d9930840f2f1394092c079` |
| Reported runtime | `4.7.2.stable.official.ed1daf0bf` |
| Runtime executable SHA-256 | `8d106cbe6144c2dc7e881d61d2429c1a8a76e6b22ef48bd5e48dcf934953f71e` |
| Generated C header SHA-256 | `640b48188708ba0016f8d7ace9e0e1d3279a41fa1226c59ff3193b15538bd254` |
| Matching interface JSON SHA-256 | `7d8c0a039d9743eb8ebf88681ae0c641d8d3aa5ffca11081745a84da803e09a1` |
| API metadata SHA-256 | `d0e4c08c03b165156dabe6bfb6a906baf0069189f62035341230a246c86d6986` |

The immutable primary interface is
[Godot's C API JSON](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/core/extension/gdextension_interface.json).
Its bytes exactly match the actual runtime export. The same process generated
the C header and API size metadata through the engine's public export flags.
No downloaded SDK or Python generator is part of this component.

The private original precommand, returned tool completion and output pins are
retained in the owning task's `api-export-result.json`. They are evidence for
the header and metadata export only. Native compilation, extension loading,
conversion behavior and live authority adoption remain separate evidence.
