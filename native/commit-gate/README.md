# Native commit coordinator

`factory-commit-check --root CHECKOUT` captures the exact staged tree, obtains
one native check/heavy permit, and invokes the existing immutable staged checker.
The checker still owns source tests, raw-blob export, index guards and required
Godot parsing. A temporary `GIT_INDEX_FILE` remains effective throughout.

[Configuration and limits](../../docs/engineering/native-builds.md#checks-and-local-hooks)
are shared with the legacy coordinator. Optional repository-local
`factory.commitGateExecutable` and `factory.commitGateSHA256` must both be valid;
both absent preserve the existing coordinator. Invalid pins or native failure
never fall back to another checker.

The native coordinator prefers worktree-specific `factory.godotArtifacts`,
then the common local setting. An empty value or read error refuses.
Engine/executable hashes remain shared. Do not wrap the hook in another
admission command.

The executable fixes `/usr/bin/git` and `/usr/bin/python3` and exposes no
command, interpreter or resource-floor override. Git metadata reads have a
five-second deadline and 2 MiB bound. Tests use disposable compiled children;
they do not themselves establish a full engine or gameplay pass.
