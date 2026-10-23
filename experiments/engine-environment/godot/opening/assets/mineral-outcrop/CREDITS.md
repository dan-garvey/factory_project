# Mineable rock outcrop

[Boulder 01](https://polyhaven.com/a/boulder_01), by Rico Cilliers, is supplied
by Poly Haven under [CC0](https://polyhaven.com/license). This package contains
adapted mesh and texture data. The provider's website and example renders are
not redistributed. Exact donor pins are in the
[source study](../../../../../../docs/art/mineral-outcrop-source.md).

The pinned Godot 4.7.2 preparation generates tangents, selects its third mesh
distance level and retains only referenced vertices: 8,264 triangles and 5,748
vertices. It recenters the mesh, then bakes a 0.45 × 0.75 × 1.25 narrow seam fit
into its positions and normal/tangent frames while preserving the donor UVs.
The compressed, material-free resource also retains the native 200-point convex
hull and its triangles, together with its original 201-point cooking input.
Bodies use that original input rather than recooking the already cooked debug
vertices. The site mount uses one specification for the immutable rock,
its native construction obstacle and actor body. This resource has no
independent mount or collision authority.
The convex envelope approximates the detailed surface, not its concavities.
Native registration and capsule-contact checks use the actual cooked hull;
this is not triangle-exact rock collision.

The color map uses a 512-pixel WebP at quality 0.84. OpenGL normals and packed
occlusion/roughness/metallic maps use 256-pixel lossless WebP after float Lanczos
resize; normal vectors are renormalized. The donor's zero metallic factor and
double-sided material are retained. Ore veins are a separate stock-derived
presentation surface; exhausting the finite reserve leaves the fixed rock.

`ore-soil.webp` is a quality-0.98 WebP derivative of generated artwork, not
part of Poly Haven's Boulder 01
package or a scanned ground material. It was made with OpenAI's built-in image
generation tool on 2026-10-22, using the adapted rock albedo only as a palette
reference. The prompt requested an evenly lit, top-down diffuse surface of
compacted tan soil, weathered bedrock chips, dark shale and restrained copper
flecks, without perspective, large boulders or baked shadows. The presentation
mesh fades this texture into terrain and removes it when the confirmed finite
source is exhausted; the image supplies no collision or stock authority.
The original 1,254-pixel PNG remains recoverable from Git commit
`f2ab158eb51b075b8d92951e535c75d035562d09` at this asset path under the
name `ore-soil.png` (SHA-256
`e3f4d5122e66a8f6f2e6f4c6e1a0eca7c2fa6da4a8d40070ef740fd7e619dab0`).
Godot 4.7.2 `Image.save_webp(..., true, 0.98)` produces the delivered 1,207,418-byte
derivative (SHA-256
`47c460f0c8546df3271a7a4f9ee875ebddb95d52bc44cc1253585268a294ce14`).

Reproduce from the pinned raw donor set with the existing
`opening/assets/foliage/prepare_maps.gd` command, using `--material=outcrop`,
`--outcrop-scale=0.45,0.75,1.25`,
an absolute `--family` containing `raw-source`, and a fresh absolute `--output`.
Geometry and image checks do not establish human visual quality.
