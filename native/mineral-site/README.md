# Finite mineral-site admission

This native component defines the first opening deposit's surface footprint and
bounded extraction clearance. The surrounding native World remains the sole
owner of remaining ore, extracted material, custody and saved state. This helper
stores no quantities or clock.

The provisional deposit covers grid tiles `[0, 0]` and `[0, 1]`. A collector must
be over that footprint, above the complete covered mineral surface and within
the declared extraction depth. The Host supplies the actual emitted terrain
height range and computes the depth from the same global height step used by
foundations. Eight current height steps are 3.3 metres, allowing a full foundation
block and sloped ground beneath it. This adds no local height origin, reach
tolerance, terrain modification or permission to float an unsupported machine.

The Host binds the reversible 4,096-unit reserve to its existing World profile,
with a 32-blank collector buffer for batch recovery. No reserve is attached to a
part instance or regenerated when machinery is moved. `source_deposit` projects
the native footprint and profile for the view. The separate
`//native/factory-godot-world:mineral_host_test` exercises admission, full finite
depletion, individual custody, cache replay and native checkpoint restoration.
The helper alone establishes no live body, rendered collector size, multiple
extractors, human quality or permanent content policy.

Run the focused native test with the admitted, pinned Bazel setup from
[native builds](../../docs/engineering/native-builds.md):

```text
bazel test //native/mineral-site:mineral_site_test
```

The canonical recursive native selection discovers this package automatically.
The test needs no engine, host fixture, desktop control or game launch.
