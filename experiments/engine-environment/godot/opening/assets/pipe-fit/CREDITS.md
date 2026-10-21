# Selected industrial pipe fitting art

Source: [Modular Industrial Pipes 01](https://polyhaven.com/a/modular_industrial_pipes_01)
by Jorge Camacho, distributed by Poly Haven under [CC0](https://polyhaven.com/license).
The source descriptor, its official [file manifest](https://api.polyhaven.com/files/modular_industrial_pipes_01),
original mesh buffer and original one-kilopixel maps are retained in the local
prototype evidence families `player-built-assets-research-20261020/candidates`
and `pipe-join-sample-20261021`. Provider preview images are not included.

This preparation selects the source meshes named `pipe01`, `pipe02` and `pipe04`
as `PipeShort`, `PipeLong` and `PipeElbow`. Their POSITION, NORMAL, TEXCOORD_0
and index accessor bytes are copied without changing vertices or UVs into a
compact 96,112-byte buffer. The source's catalogue-layout node translations
are removed; the three prepared nodes all have identity transforms and overlap
at the origin until a consumer mounts them separately. The 1K Group 01 diffuse
and normal JPEGs are byte-identical to their official source files. The Group
01 packed ARM map was decoded from the original 1K JPEG, resized to 256 pixels
with Godot 4.7.2 Lanczos interpolation, and saved as PNG without another lossy
encode. The complete prepared five-file resource set is about 1.45 MB. Exact
source-to-output hashes and the preparation program are retained in
`pipe-join-sample-20261021/prepared-resource-manifest.json` outside Git.

Candidate connection frames in each mesh's local coordinates, in glTF metres:

| Piece | End frames and outward normals |
| --- | --- |
| `PipeShort` | `(0, -0.429531, 0) / -Y` and `(0, +0.429531, 0) / +Y` |
| `PipeLong` | `(0, -0.977320, 0) / -Y` and `(0, +0.977320, 0) / +Y` |
| `PipeElbow` | `(-0.296728, -0.086859, 0) / -X` and `(0.023870, 0.254192, 0) / +Y` |

Align centers and **opposing** outward normals. The retained first passive elbow
render aligned centers with parallel normals and left an exposed upward flange;
the corrected render has the intended bolted join. These are visual candidate
frames, with no asserted socket tolerance, collision, pressure, fluid or native
construction rule. The asset is not mounted in the playable opening yet. An
actual presenter should instantiate the selected mesh and material from these
tracked resources, and keep mechanical authority in the existing native
World and Host.
