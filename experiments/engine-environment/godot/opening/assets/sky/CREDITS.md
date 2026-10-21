# Worksite daylight

[Kloppenheim 03 (Pure Sky)](https://polyhaven.com/a/kloppenheim_03_puresky)
is an edited sky-only photograph by **Greg Zaal**, with sky edits by
**Jarod Guest**, supplied through Poly Haven under [CC0](https://polyhaven.com/license).
The delivered file is the provider's original 1024×512 Radiance HDR, preserved
byte-for-byte. It is not the website's example render or tone-mapped preview.
[source.json](source.json) records the source URL, checksums and measured input.

The runtime image is converted from RGBE to floating RGB and given mipmaps once.
It is not resized, tone mapped, gamma converted or recompressed on disk. The
existing panorama material supplies the sky, ambient and reflection environment.
Exposure remains one with the existing ACES tone mapper. The key light keeps its
existing intensity and warm tint, while its direction follows the brightest
source texel centre. This avoids a second, unrelated painted sun direction.
The initial resolution, exposure and light intensity remain reversible art
choices, not weather, time-of-day rules or a photometric calibration.

The coordinate mapping was checked against the runtime revision's
[Compatibility sky shader](https://raw.githubusercontent.com/godotengine/godot/ed1daf0bf001b61586d9930840f2f1394092c079/drivers/gles3/shaders/sky.glsl)
and [panorama material](https://raw.githubusercontent.com/godotengine/godot/ed1daf0bf001b61586d9930840f2f1394092c079/scene/resources/3d/sky_material.cpp).
It uses the texel-centred longitude and latitude without an extra half-turn.
The measured bright texel is at `(614, 89)`, about 58.5 degrees above the horizon.
This establishes source-to-node orientation, not a rendered shadow measurement.

The original asset, provider metadata, source qualification, disposable display
preview and engine-source pins remain in `sourced-worksite-sky-20261021` outside
Git. The preview uses a display transform only for source inspection; it is not
the delivered HDR or a game capture. Historical fixed source rosters retain the
earlier generated panorama. Geometry, collision, construction and actor authority
are unchanged. Resource controls do not establish rendered lighting balance,
GPU cost, human preference or the overall production-quality target.
