# Grass ground surface

The current ground uses [Grass 001](https://ambientcg.com/view?id=Grass001) from
ambientCG under [CC0](https://docs.ambientcg.com/license/). The provider describes
fresh, dense, short green grass and declares a 1.4-metre square tile. This is a
reversible art choice for the first worksite. The exact 1K JPG archive and four
source member hashes are recorded in [source.json](source.json). The prior Brown
Mud Leaves 01 surface and its original evidence remain in Git history.

The source color JPEG is decoded to 1024-pixel RGB8 and stored as lossless WebP;
its decoded pixels are preserved without resizing or color transformation.
Separate JPEG OpenGL normal, ambient occlusion and roughness maps are decoded in
the pinned Godot runtime and resampled at 512 pixels with float Lanczos filtering.
Red in the packed data map holds occlusion, green holds roughness and blue is zero
metallic. The resampled normal is normalized before nearest-byte RGB8 packing;
its maximum encoded unit-length error is recorded in source.json. No normal
green flip or data gamma operation is applied. The prepared maps roundtrip through
lossless WebP without a decoded-pixel change. Runtime generates mipmaps and
renormalizes the normal mip chain.

The shared terrain shader projects the three maps in world space at the declared
1.4-metre scale, with stationary randomized patches and broad color variation.
It does not raise grass blades or alter terrain, collision, quantities or state.
The existing grass tufts supply separate near-field geometry. Map and isolated
render checks are bounded presentation evidence, not human play or acceptance of
the complete game scene.
