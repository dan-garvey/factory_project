# Foundation concrete surface

The source is [Concrete Floor 01](https://polyhaven.com/a/concrete_floor_01) by
**Rob Tuytel**, supplied by Poly Haven under [CC0](https://polyhaven.com/license).
Its photographed exposed-aggregate surface covers two metres by two metres.
The original one-kilopixel JPEG albedo is retained without re-encoding.

The OpenGL normal and packed scalar maps come from the provider's lossless PNG
versions. The existing generic component-map preparation converts them to linear
float images, resizes with Lanczos, renormalizes tangent normals and rounds once
to RGB8. Lossless WebP decoding reproduces every prepared pixel. The normal's
maximum encoded length error is 0.005042 and angular error is 0.344 degrees.
No normal-axis flip or color-space transform is applied. The preparation tool's
existing `cast` output prefix is renamed for this concrete resource; it does not
identify the source material. Exact source and prepared hashes are in
[source.json](source.json).

The cached concrete material uses the source albedo, green roughness channel and
OpenGL normal. It is nonmetallic and leaves the unused occlusion and metallic
channels unbound. World-space triplanar mapping retains the two-metre scale across
stationary tiles and stacked sections. Mipmaps add no geometric displacement.

This is an authored visual finish for the provisional foundation kit, without a
new recipe, wear, structural-load or collision rule. Source qualification and
resource views cannot establish the actual app result or human quality.
