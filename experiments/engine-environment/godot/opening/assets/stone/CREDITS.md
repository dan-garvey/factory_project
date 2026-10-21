# Weathered natural stone

[Rock 3](https://polyhaven.com/a/rock_3) by **Rob Tuytel** is supplied through
Poly Haven under [CC0](https://polyhaven.com/license). The provider describes a
1.5-metre square photographed rock face. This package uses the source maps, not
the website's example renders or its optional preview mesh. Original downloads,
metadata and results remain in `sourced-worksite-stone-20261021` outside Git.
[source.json](source.json) records their exact identity and the packaged files.

The 1024-pixel sRGB color uses WebP quality 0.80, with measured error below the
declared 0.025 root-mean-square bound. The first quality-0.70 output failed that
bound and remains intact. Only color was reencoded; the original passing normal
and scalar outputs were rehashed and reused. The complete package remains below
its declared one-million-byte bound. These numerical limits are not a visual
quality verdict.

The OpenGL normal is Lanczos resized to 512 pixels, vector-normalized and
explicitly nearest-rounded to RGB8. Linear packed red occlusion, green roughness
and blue metallic are resized to 256 pixels with the same explicit rounding.
Both use lossless WebP. No data-map gamma transform or normal green flip is
applied. The material preserves the provider glTF's zero metallic factor and
generates mipmaps once, with normal-vector renormalization. World-space triplanar
scale `1 / 1.5` preserves the source repeat rather than stretching one texture
over every rock. Restrained instance tint keeps the photograph's brightness.

To reproduce the maps, place the verified source files under their manifest names
in a fresh owned family. Through ordinary resource admission, run the pinned
Godot executable with:

```bash
--headless --audio-driver Dummy \
--path experiments/engine-environment/godot \
--script res://opening/assets/foliage/prepare_maps.gd -- \
--family=/absolute/owned/source-family --material=stone
```

The shared preparation script keeps its original foliage mode as the default.
The stone mode creates a fresh `prepared-stone` directory and retains decode,
color-error, unit-normal and package-size results. It refuses existing outputs.

The shared material is consumed by the natural geological pieces and existing
rock group. Their meshes, rigid transforms, collision descriptors and actor
authority are unchanged by this material increment. No source displacement,
new mineral identity or scanned silhouette is implied. Historical source rosters
without these maps retain the previous generated finish. Partial or invalid
sets report their status instead of claiming a complete source material.
