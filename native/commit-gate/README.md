# Native commit coordinator

`factory-commit-check --root CHECKOUT` captures the exact staged tree, chooses one
native check or heavy admission, and runs the existing
`python3 -B scripts/check.py --staged --expected-tree TREE` command. Supported
GDScript deltas also carry the same three repository-local Godot settings and
compiler flags as the legacy coordinator. A temporary `GIT_INDEX_FILE` remains
in effect for selection and the outer checker.

The native resource library supplies the existing four heavy slots, jobs,
capacity floors, shared lock files and child lifetime. Source checks, raw blob
export, snapshot isolation, index guards and compiler validation still belong
to the unchanged staged checker. This component does not finish native gate
migration or run game/desktop tests.

The host fixture uses a compiled child to observe exact arguments, environment
and exit propagation. Its independent sibling holds one synthetic repository's
native heavy slot while another coordinator completes. Existing resource-library
controls are reused. The fixture has no Python implementation and starts no
engine; it is not evidence of a game or full compiler pass.

The installed executable fixes `/usr/bin/git` and `/usr/bin/python3`; it exposes
no command, interpreter, slot, job or capacity override. Git metadata reads have
a five-second deadline and a 2 MiB output bound. The unchanged checker continues
to reject stale indexes and invalid staged snapshots.

The existing hook installer stays unchanged. Optional repository-local
`factory.commitGateExecutable` and `factory.commitGateSHA256` settings select a
retained tested binary. Both absent keys preserve the legacy command; partial
configuration, a noncanonical path, a changed pin or native failure never selects
another checker. [CONTRIBUTING](../../CONTRIBUTING.md#checks-and-local-hooks)
documents activation. The separate dispatch fixture covers this glue without
repeating the coordinator's accepted controls.
