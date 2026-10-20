# Scanned steel foundation surface

The source is [Metal Plate 02](https://polyhaven.com/a/metal_plate_02) by
**Rob Tuytel**, supplied by Poly Haven under [CC0](https://polyhaven.com/license).
The original photographed surface covers two metres by two metres. Its sheet
joints are used on the foundation panels, never wrapped onto machined bearings.

The albedo remains 1024 pixels square, encoded as WebP at quality 0.50 without
a color-space transform. Its measured sRGB root-mean-square error against the
original provider image is 0.016958, below the retained 0.025 preparation bound.
The 1024-pixel OpenGL normal and 512-pixel Lanczos-resized packed linear occlusion,
roughness and metallic maps use lossless WebP. Every decoded data-map pixel equals
the preceding prepared PNG, with no normal-channel flip or color-space transform.
Original downloads and the preparation program/results are retained in
the author's external evidence. `source.json` records source and processed hashes.

The normal EXR variant was rejected by the pinned engine's TinyEXR loader because
of its compression type; that original file and failure remain preserved. The
working import uses the same provider's OpenGL PNG representation. This is a
specific import-format limitation, not a graphical engine ceiling.

World-space triplanar mapping keeps the material continuous across the static
panels. Mipmaps are generated once, with normal-vector renormalization. No source
displacement map, physical floor change, renderer switch or game rule is added.
Historical fixed-roster payloads with no bitmap set retain the procedural floor;
partial or invalid sets report an error rather than being labeled as scanned.
