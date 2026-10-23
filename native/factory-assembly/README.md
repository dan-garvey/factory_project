# Chapter assembly geometry

This native helper inspects World-owned placed components against a trusted ore
face. A wooden frame, tool mount, cutting edge, receiver and wooden or softmetal
shaft must form a contiguous quarter-grid arrangement. The cutter can sit at
frame height or one quarter step above it; the receiver and drive may use
different sides. The ore face supplies a workcell and direction, so the helper
does not hard-code one deposit coordinate, special build rectangle or local
height origin.

The result is derived and read-only. It does not create material, activate a
collector, claim a shaft source, select among multiple complete arrangements or
provide scene clearance. Ambiguous complete layouts are reported rather than
silently choosing one. World integration must retain the same placed identities
and native material ledger, admit actual contact/drive/receiver clearances, and
reuse the existing finite ore source and output custody. The test checks two
distinct complete layouts, rotated and raised workcells, incomplete assemblies,
invalid identities and ambiguous drive choices. These are geometry controls,
not a running collection or human-play result.

`inspect_press` reads the same placed-part identities at any four-step frame
origin. A distinct anvil, ram face, sliding guide and tool mount rise one
quarter-grid step at a time above the frame. A wooden or softmetal shaft and
cog approach the mount from one horizontal side; a second complete drive is
reported as ambiguous. The lower anvil level exposes all feed/exit pairs that
remain clear of placed components. A raised frame uses the same absolute
height denominator. This older framed arrangement remains a fixture while
its consumers migrate.

`inspect_guided_press` instead anchors at a placed anvil on the shared
four-step grid. The ram face is one quarter step above it, the unmounted
sliding guide is three steps above it, and a shaft with a cog approaches at
the next full-grid axle height. No frame or tool mount is required. The same
clear-feed and ambiguous-drive refusals apply at ground or raised height.
Assembly inspection remains read-only; native World owns power, work and
material custody, while Host and the ordinary scene still need this new
arrangement as consumers.
