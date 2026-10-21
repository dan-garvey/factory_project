# Timber waterwheel paddles

The timber surface is adapted from **Fine Grained Wood**, by **Rob Tuytel**,
published by [Poly Haven](https://polyhaven.com/a/fine_grained_wood) under
[CC0](https://polyhaven.com/license). The provider preview and website copy are
not included. The blade, cleat, strap and bolt geometry is original Factory art.

The current asset page and numeric dimensions indicate about 0.6 metres, while
the older API scale string says `30x30CM`. The 0.6 metre runtime mapping is an
explicit experimental visual choice. Grain V follows the longer axial span of
each blade. A dedicated end-grain texture is not supplied by this increment.

The color is the original one-kilopixel JPEG. Normal and roughness data are
prepared at 512 pixels with float Lanczos sampling, OpenGL normal renormalization
and nearest RGB8/L8 encoding. WebP delivery is lossless relative to those prepared
pixels, not identical to the larger source PNGs. The slightly nonopaque source
alpha has no material role. Full RGB hashes match an independent PNG decoder,
and every data pixel remains exact when converting to float RGB before resizing.
[Godot's material documentation](https://docs.godotengine.org/en/4.7/classes/class_basematerial3d.html#class-basematerial3d-property-normal-texture)
describes the normal channels; roughness explicitly selects red. The original
opacity-assumption refusal remains in the external preparation evidence.

The twelve original paddle positions, sourced rotor, native spindle axes,
conservative envelope and signed presentation angle remain. These thin blades
and fitted root details do not change power, efficiency, material or collision
rules. Missing historical map sets retain their earlier block paddles and finish.
The normal native launcher captures all resources locally. Packaged exports,
rendered quality, GPU cost and human assessment remain unverified.

[source.json](source.json) records source and delivered hashes and processing.
Reproduce the maps through the existing machine-detail script's
`--prepare-paddle-maps SOURCE_DIRECTORY FRESH_OUTPUT_DIRECTORY` entry.
