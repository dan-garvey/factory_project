# Godot and adapter constraints

Current working reference for **Godot 4.7.2**, source
`ed1daf0bf001b61586d9930840f2f1394092c079`. [DESIGN](../../DESIGN.md) owns gameplay.
These limits do not become game requirements. New investigations and dated
results belong in their owning Beads; update this reference only when a current
constraint changes. Historical GDC investigations remain in `factory-yau.3.10`
and the linked implementation tasks.

## Engine and API

- Scene-tree mutation and engine values belong on the engine-owning thread;
  data-only native parallelism is a separate boundary. See
  [thread-safe APIs](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html).
- Requested transforms, rendered transforms and physics-confirmed poses differ.
  Construction/reach uses confirmed native actor facts, not camera or interpolated
  presentation. `CharacterBody3D` settings do not prescribe the game's movement.
- Far-origin precision needs representative measurement. Ordinary vectors and
  scalar floats have different precision; origin shifting/double builds have
  costs. No arbitrary world-size cap follows from the initial fixture.
- Renderer/version logs do not identify the physics backend. Qualify backend,
  settings and build before comparing behavior; no general Physics/Jolt parity
  or moving-save guarantee has been established.
- JSON parsing cannot attest integer RPC Variants. Preserve exact typed values
  across commands, checkpoints and the native
  [value adapter](../../native/factory-godot-values/README.md).
- Dictionary `StringName` ordering is not lexical text order. Do not use a
  reported first key as a stable tool-name oracle.
- Short segment/triangle queries can lose small faces to an absolute epsilon.
  Test the intended scale. `Mesh.get_faces()` uses a triangle cache snapped to
  a 0.0001 grid; inspect surface vertex/index arrays for exact render geometry.
- `SurfaceTool.append_from()` does not fill missing indices when mixing indexed
  and unindexed inputs. Normalize indexing before combining surfaces.
- Runtime `Image.generate_mipmaps()` does not preserve alpha-cutout coverage.
  The grass adapter preserves border color and adjusts coverage per mip.
- Native Array export resizes once and checks every indexed write's validity
  and bounds; retain type, ownership, nesting and quantity limits.
- Embedded `PopupPanel` can hide on root-viewport resize. Preserve the user's
  open/dismissed state through layout changes, and test the ordinary path.

## Current adapter boundaries

- The native World owns gameplay state. Headless GDScript fixtures are still
  engine-coupled; a headless run alone does not prove portable authority.
- Sampled port/contact probes do not establish swept clearance, arbitrary rigid
  item dynamics, docking forces or independent-machine pushing.
- The construction pointer requests a datum. Terrain support and build admission
  require their actual sampled/native conditions; a fallback ray cannot grant
  terrain permission. Foundations and transmission share the global datum.
- Transmission stands and landing-pod meshes are derived presentation. They
  must match native occupied/support geometry and the one saved pod identity;
  art cannot create another foundation, reserve or machine.
- A carried multitool belongs to the actor presenter, not another physical actor.
  Confirmed actor updates may arrive slower than render frames; measure elapsed
  time between fresh positions. `native_epoch` is an ordinal, not a timestamp.
- Cosmetic transmission phase may interpolate confirmed signed rates, but
  cannot advance production. Authority changes invalidate tick-delta comparison
  bases; any field changed by a World tick must match full projection.
- Shared native delivery separates reliable commands/outcomes, compact replaceable
  actor views and reliable full state with acknowledgements/watermarks. A bounded
  loopback result does not establish internet loss tolerance, prediction,
  rollback, adversarial movement admission or production scale.
- Store persists explicit game state, not arbitrary live scenes or every engine
  object. Stationary continuation does not prove crash durability, cross-version
  migration, moving passengers or every shared-world scenario. Failed native
  loads must not fall back to a fresh/scripted world.

## Rendering and measurement

- Compatibility rendering, fixture window sizes and source/log budgets are
  tooling choices, not a graphical-quality ceiling or game-scale acceptance.
  Inspect the actual renderer/GPU; WSL software rendering is not target GPU proof.
- Import resources before checking widgets. Retained compiled resources must
  belong to the captured project. Exit zero or a PASS marker with engine errors
  is failure.
- Headless MultiMesh readback can differ from graphical rendering. Use graphical
  captures for visible batch poses, scale, connections and picking.
- Measure cold setup separately from active animation. Packing scenes does not
  remove first-use node/material/GPU cost. Reusing loaded wheel art avoids
  procedural setup for unbaked sizes; profiles still need current inputs.
- Batch compatible opaque surfaces while preserving material boundaries, native
  transforms and picking. Static batches have renderer-dependent cost; update
  visible belt instances when their phase changes. Shared primitives can express
  irregular support heights without inventing a second height grid.
- Passive captures and invented-cargo widgets establish only their visible
  conditions. They are not ordinary-input, native custody, performance or human
  understanding evidence.

Use [resource admission](local-resources.md) and
[build/runtime configuration](native-builds.md). Keep unresolved limits explicit
in Beads; do not delay the chapter for an exhaustive engine characterization.
