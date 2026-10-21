# Variable-bay press frame sample

This is a passive art study for the [player-built asset system](player-built-assets.md),
not a new machine or construction rule. The source was the exact tracked Godot
project at commit `76c5117d0c717362b8d95ed049d6ea384f6c81c2`. The isolated
sample reused its sourced cast press supports, authored crown, die, anvil,
formed output pan, machined finishes and C-channel skid. It did not change
game code or instantiate native World state.

The source, renderer, original and revised frames, logs and byte hashes are
retained outside Git under `multi-press-frame-20261021/audit.json` in the local
prototype evidence directory. Twelve final 1200 × 900 images cover front,
rear and construction-distance views of these four assemblies:

| Assembly | Bay spacing | Structural treatment |
| --- | ---: | --- |
| Two duplicated presses | 1.35 m | Two complete, adjacent skids and crowns. This is the comparison baseline. |
| Two close shared bays | 1.35 m | The 1.35 m rigid skid bays meet; a 0.15 m plain crown middle and fixed seam plates join unchanged detailed ends. |
| Two wide shared bays | 2.10 m | A 0.75 m plain skid middle and 0.90 m crown middle connect the original rigid ends. |
| Three close shared bays | 1.35 m | Three rigid bays and two repeated joints use the same component rules. |

The authored press support still mounts on its original Y = 0.24 m deck datum.
Each tool, anvil and output pan keeps its original local shape and offset. The
generated lengths affect plain central spans only; they do not scale the source
column, fasteners, tool face, pan or flange. Existing planar UVs follow local
physical dimensions instead of stretching a fixed complete machine texture.
The original press head's lower face is at Y = 0.755 m at rest. The current
source-derived held-work pose lowers it by 0.015 m, leaving 0.008 m above the
existing billet boss at Y = 0.732 m. This is an arithmetic source check, not a
new held-work render or native contact measurement. At the close spacing, the
neighboring tool heads have at least 0.79 m between their declared horizontal
boxes, and each output pan's declared right edge stays 0.30 m short of the next
anvil's left edge. Detailed facet contact and a real item route remain untested.

I inspected the final front and rear variants and the construction-distance
view, against the earlier duplicated and continuous-slab samples. Reusing the
real C-channel skid bays makes the foundation of the assembly more credible than
stretching one dark slab. The separate output pans remain visibly unobstructed
in the isolated close views. The joint plate and bolt detail helps a close
seam read as intentional, while the wider crown middle visibly remains a plain
unsupported crossbar. At construction-camera distance, the repeated tool
modules are legible as a row, but the small seams and individual output pans
are difficult to distinguish. No input, material path or mechanical drive is
shown, so the composition cannot yet explain how a player-built multi-press
would operate. Three copies of today's press do not meet the graphical target.

The first comparison placed its separate skid mesh 0.12 m too low; those images
are retained and excluded from the corrected mounting comparison. A later
version replaced the plain shared slab with rigid skid bays and generated gap
pieces. The final renderer completed with no script or import error, but its
captured source still used raw project image reads and emitted seven export
warnings. This sample is visual evidence from an isolated renderer, not a
packaged export or a new normal-game view. The separately reviewed imported
image fix has its own source and tests; this study does not replay or claim it.

The next art increment needs authored **intermediate and terminal frame joints**,
a supported long crosshead with purposeful braces, a repeated skid connector
and exposed-end caps. Give press and cutter modules different tool silhouettes,
guards and work openings. Keep rigid detailed parts at fixed size and generate
only the length-dependent rails or panels. Those assets must attach to confirmed
part identities, orientations, structural joins, material outputs and motion
from the sole native World. The current native profile does not yet expose a
player-selected multi-press or combined press/cut assembly; the sample grants
no such function. A useful first implementation would present two confirmed
press modules on a shared frame in the ordinary worksite, verify their distinct
tool and output clearance at rest and held work, and compare close and normal
camera views with human feedback. These are future acceptance conditions, not
claims made by this isolated sample.
