# Mineable rock outcrop

[Boulder 01](https://polyhaven.com/a/boulder_01), by Rico Cilliers, is supplied
by Poly Haven under [CC0](https://polyhaven.com/license). This package contains
adapted mesh and texture data. The provider's website and example renders are
not redistributed. Exact donor pins are in the
[source study](../../../../../../docs/art/mineral-outcrop-source.md).

The pinned Godot 4.7.2 preparation generates tangents, selects its third mesh
distance level and retains only referenced vertices: 8,264 triangles and 5,748
vertices. It recenters the mesh without changing its scale, normals or UVs.
The compressed, material-free resource also retains the native 200-point convex
hull and its triangles, together with its original 201-point cooking input.
Bodies use that original input rather than recooking the already cooked debug
vertices. The later site mount must use one specification for the immutable
rock, its native construction obstacle and actor body. This package alone
does not mount a new obstacle in the playable opening.
The convex envelope approximates the detailed surface, not its concavities.
The measured maximum mesh protrusion is below 0.2 millimetres after native
hull cooking; this is not triangle-exact rock collision.

The color map uses a 512-pixel WebP at quality 0.84. OpenGL normals and packed
occlusion/roughness/metallic maps use 256-pixel lossless WebP after float Lanczos
resize; normal vectors are renormalized. The donor's zero metallic factor and
double-sided material are retained. Ore veins are a separate stock-derived
presentation surface; exhausting the finite reserve leaves the fixed rock.

Reproduce from the pinned raw donor set with the existing
`opening/assets/foliage/prepare_maps.gd` command, using `--material=outcrop`,
an absolute `--family` containing `raw-source`, and a fresh absolute `--output`.
Geometry and image checks do not establish human visual quality.
