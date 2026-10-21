# Rocky-ground surface

The source is [Rocky Trail](https://polyhaven.com/a/rocky_trail) by **Amal Kumar**,
provided by Poly Haven under [CC0](https://polyhaven.com/license). The provider
reports a two-metre square surface. These photographed maps supply shading only;
the original shared terrain triangles and ActorWorld remain authoritative.

The albedo keeps its 1024-pixel extent and sRGB representation. WebP quality 0.70
has measured sRGB root-mean-square error 0.023997 against the provider JPEG, below
the declared 0.025 packaging bound. This numerical bound is not a visual verdict.

The packed PNG supplies linear red ambient occlusion, green roughness and blue
metallic. It is decoded to RGB8, Lanczos resized to 512 pixels and saved as
lossless WebP. The material retains the provider glTF's zero metallic factor.
The 16-bit OpenGL normal PNG is decoded to RGB8, resized to 512 pixels and
renormalized. Explicit nearest-integer packing limits the measured unit-vector
error to 0.006527; lossless WebP preserves those prepared bytes. No gamma transform
or green-channel flip is applied to either data map. Runtime normal mipmaps are
renormalized, and world-space triplanar scale 0.5 preserves the two-metre extent.

The source files, metadata, preparation programs and results remain in the
author's external `scanned-valley-ground-20261020` family. A valid larger normal
representation did not fit the unchanged source allowance. The first 512-pixel
writer failed its original unit-vector bound; that output and result remain
intact alongside the corrected encoding. Albedo and scalar preparation were not
repeated. [source.json](source.json) records exact source and packaged hashes.

Missing historical bitmap sets retain the procedural surface. Partial or invalid
sets report their status and are never labelled as ready scanned material.
No new displacement, collision, renderer selection or game requirement is added.
