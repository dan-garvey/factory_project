# Mineral outcrop source study

The first-shift mineral deposit currently reads as a shallow ground patch at
construction distance. A substantial rock could establish the source as part of
the landscape, but its visible shape must agree with native placement
obstruction and actor collision. This study qualifies a donor model for that
later integration. It does not place a rock in the playable site.

## Candidate and visual finding

[Boulder 01](https://polyhaven.com/a/boulder_01), by Rico Cilliers, is a
[CC0](https://polyhaven.com/license) boulder with a
fractured face, warm mineral-colored streaks and some lichen. Its approximately
1.8-metre width suits a local source better than a whole cliff model. Poly
Haven's page lists 123,976 triangles, while the downloaded 1K glTF itself has
one mesh with 67,042 positions and 66,122 indexed triangles. The imported local
bounds are 1.272 by 1.004 by 1.830 metres. Use the delivered mesh count when
estimating this candidate's rendering cost; neither number is a measured
many-instance budget.

Two lower-triangle sources were also considered from their provider pages:
[Rock Face 01](https://polyhaven.com/a/rock_face_01) spans about 7.1 metres and its
[provider metadata](https://api.polyhaven.com/info/rock_face_01) lists 20,174
triangles, while [Rock Face 02](https://polyhaven.com/a/rock_face_02) spans about
4.9 metres and its [metadata](https://api.polyhaven.com/info/rock_face_02) lists
29,566. They are cliff-face candidates rather
than an obviously freestanding source node. Neither was downloaded or imported
in this study. The choice of Boulder 01 is provisional and remains subject to
the actual worksite composition, occlusion and collision fit.

Godot 4.7.2 imported the unmodified model with one textured mesh and no donor
script or collider. Its color, normal and roughness maps were present at the
declared 1K resolution. An isolated Compatibility-renderer fixture passed 18
source and image checks. Personally inspected front and back views show a
legible, irregular rock silhouette and much richer surface relief than the
current patch. They show no terrain contact, collector placement, actor path,
depletion state or human assessment. The retained passive images, full log,
fixture and provider files are linked from `factory-yau.6.45.21.27.1` in the
private project tracker.

## Exact donor files

The [provider metadata](https://api.polyhaven.com/info/boulder_01) and
[file index](https://api.polyhaven.com/files/boulder_01) were read on
2026-10-22 UTC. The files below are the provider's unmodified 1K glTF set. Their
total size is 5,771,986 bytes. These pins allow a future adapter to reproduce
the study without treating an unversioned asset name as an exact input.

| File and direct source | Bytes | SHA-256 |
| --- | ---: | --- |
| [Scene](https://dl.polyhaven.org/file/ph-assets/Models/gltf/1k/boulder_01/boulder_01_1k.gltf) | 2,773 | `51487934db898b4c24072780a451e34eca5c02e3ada24a62bbc600bbc4019e92` |
| [Geometry](https://dl.polyhaven.org/file/ph-assets/Models/gltf/8k/boulder_01/boulder_01.bin) | 2,938,808 | `7f5b06503d62bd95bfe9c6b8a354a5cc8ff04a4d271a8cf87a3e3125db4232d7` |
| [Packed occlusion, roughness and metal](https://dl.polyhaven.org/file/ph-assets/Models/jpg/1k/boulder_01/boulder_01_arm_1k.jpg) | 659,386 | `c57187c5746b6be913fa53846cb44ff78743e7ca5000f131c9627b99563c2b87` |
| [Color](https://dl.polyhaven.org/file/ph-assets/Models/jpg/1k/boulder_01/boulder_01_diff_1k.jpg) | 987,467 | `c38f0e918f6dc16b8d386ba3cdd89805c78320c119a1ceec85856f82b09a65b8` |
| [OpenGL normal](https://dl.polyhaven.org/file/ph-assets/Models/jpg/1k/boulder_01/boulder_01_nor_gl_1k.jpg) | 1,183,552 | `0810cf6e89d89bb6eb065b4d2e2855288f5dcbd2c15c6e40ab90d462021b50aa` |

## Packaging and integration boundary

The first staged source candidate included those five donor files and an
isolated GDScript fixture. Its installed hook passed 153 tooling tests, then
stopped before compilation because the staged Godot project exceeded its
explicit 32 MiB source allowance. The measured project files totaled
39,293,317 bytes with the candidate and 33,512,113 bytes without its folder,
leaving only 42,319 bytes below the allowance. That is a packaging constraint,
not evidence that the model failed to import or render. The original failed
hook diagnostic remains in the tracker evidence. The donor and fixture are
retained outside Git; this source note adds no new runtime asset to the game.

The later outcrop should either prepare a smaller delivered model within the
existing captured-source budget or make an explicit resource-scope decision.
Its single site-surface specification must drive visible placement, native
terrain obstruction and actor collision. The finite mineral overlay can deplete
while the geology remains. Collector reach, starter space, water-edge clearance,
walking and save behavior require their own relevant checks. The isolated
source view does not accept those outcomes or the production-quality target.
