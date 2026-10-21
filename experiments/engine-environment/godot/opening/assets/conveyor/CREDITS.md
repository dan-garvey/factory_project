# Conveyor rubber and authored assemblies

The conveyor surface uses [Rubber 004](https://ambientcg.com/a/Rubber004) from
ambientCG, under [CC0 1.0](https://docs.ambientcg.com/license/). The provider
records an approximate 75 by 75 centimetre extent. Its retained API response uses
the method code `PBRProcedural`, but its descriptive labels identify photogrammetry.
That conflict leaves the exact creation technique unverified. The asset is not
evidence of a photographed conveyor or a belt performance specification. The
original maps and license capture are retained outside Git in
`conveyor-component-kit-20261021`; identities are in [source.json](source.json).

The one-kilopixel archive supplies color, OpenGL normal and scalar roughness.
Albedo retains exact decoded RGB8 pixels at its original resolution. Linear data
maps are resized to 512 pixels in floating precision; normals are normalized
before nearest RGB8 encoding and roughness is rounded to L8. Lossless WebP
preserves the prepared pixels. The pinned engine decodes the source 16-bit normal
PNG to RGB8 first; this does not preserve every source bit. There is no axis flip,
metallic map, baked occlusion or displacement. Runtime mipmaps are generated once,
with normal renormalization.

Factory authors the closed ribbon, small edge bevels, turned drums and supports.
The loop has a 1.14 metre center span, 0.09 metre outer return radius, 0.012 metre
thickness and 0.64 metre width. Its top retains the earlier cleats' 0.555 metre
height. Four complete longitudinal texture repeats close the visible loop seam;
each is about 0.7114 metres rather than exactly 0.75. Across the section, UVs
follow physical distance at the nominal source scale, with an inner-edge unwrap
seam. No whole assembly is stretched.

Two rigid drums retain their original centers; supports stand outside the return.
Existing rails, bearings, routes, workpiece positions and native drive mount
remain. Static rubber does not infer surface speed, direction or phase from
production ticks. Cached geometry and materials have no collision, input or state
authority. Historical rosters without images use generated rubber on the same
loop; partial sets are invalid. Resource and mesh checks do not establish
rendered quality, native contact or the user's visual preference.

Reproduce maps through the existing machine-detail fixture's
`--prepare-conveyor-maps SOURCE_DIRECTORY PREPARED_ASSET_DIRECTORY` entry after
importing a complete captured project. It requires the three pinned source PNGs
and fresh outputs. This image adapter adds no game or Python implementation.
