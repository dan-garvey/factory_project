# Cast and worked transmission surfaces

Cast rims and spokes use the normal and roughness maps from
[Metal 041 A](https://ambientcg.com/a/Metal041A), an ambientCG material under
[CC0 1.0](https://docs.ambientcg.com/license/). Its retained API code says
`PBRProcedural`, but the adjacent labels describe photogrammetry. That conflict
leaves the original creation technique unverified. The source supplies no physical
extent. Factory selects a revisable 0.25 metre repeat and a 0.35 normal strength;
these are art choices, not measured casting dimensions. Color, metalness and
displacement maps are deliberately omitted. The presenter's existing operating
tint remains unchanged and does not identify a chemical alloy.

Original source bytes and license evidence stay outside Git under
`machined-transmission-surfaces-20261021`; [source.json](source.json) identifies
the selected files. The original normal PNG is 16-bit, but the pinned engine
decodes it to RGB8. Preparation then resizes linear data in float precision,
normalizes vectors and rounds to RGB8 or scalar L8. Lossless WebP preserves the
prepared pixels, rather than every original source bit. There is no gamma
conversion or normal-axis flip. Runtime normal mipmaps are renormalized.

Teeth, hubs, fasteners, shaft bodies and collars use original Factory worked
surface maps. A periodic, smoothly blended noise recipe combines fine grain and
restrained bands in an 80 millimetre tile. Finite differences of the disclosed
10 micrometre height amplitude author tangent normals; they never displace mesh
vertices or model wear, damage, contact or friction. Scalar roughness stays
between 0.28 and 0.42. This is a stylized worked finish, not a scan or proof of a
particular machining process. Copper-colored keys retain their earlier material.

All four maps are generated offline by the existing transmission fixture's
`--prepare-transmission-maps SOURCE_DIRECTORY PREPARED_ASSET_DIRECTORY` entry.
It checks the pinned source PNGs before writing and refuses existing outputs.
The fixed recipe and engine version make this local preparation reproducible.
These maps require no runtime noise generation or file writing.

The ordinary presenter shares cached materials and images between compatible
parts. Local-space triplanar mapping follows each rigid part as it rotates and
uses mesh coordinates in metres, preserving density on different shaft lengths.
It does not alter mesh data, picks, native axes, identities, rates or phase.
Historical captures without the entire set retain their earlier generated
finish; partial sets are invalid. Raw-file loading is verified for the native
captured project, while packaged exports remain unverified. Isolated assignment,
pixel and resource checks do not establish rendered quality or GPU cost.
