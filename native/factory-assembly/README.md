# Collector assembly geometry

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
