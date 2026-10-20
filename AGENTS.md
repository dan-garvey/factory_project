# Agent Instructions

## Communication

Write complete sentences with normal word spacing in chat, Beads, notes and
handoffs. Concise does not mean compressed. Keep identifiers separate from the
surrounding prose and explain unfamiliar abbreviations.

Keep routine coordination in the owning Bead. Notify the PM only for an actionable
handoff, a material finding, a resource conflict or a decision outside your scope.
Use a short outcome, what it means, the next action and one task/comment reference.
Put detailed hashes, commands, counters and resource tables in structured evidence;
do not forward those records verbatim into the user's conversation.

Use these instructions as the writing standard, not old messages or session logs.
Rewrite or remove malformed prose from agent-facing records rather than preserving
it as a quoted example, an appended correction or a duplicate archive. Retain the
necessary technical facts in clear language. Do not erase or relabel actual test
results, and never turn a wording cleanup into a passing test.

## Self-management and review

Agents own their work queues and coordinate tasks, dependencies, peer reviews and
local resources directly. The progenitor is a reviewer and integration owner, not
a routine dispatcher or supervising approval gate. Course corrections belong in
specific Bead details and review findings or rejections, with a concrete reason
and acceptance condition. Do not wait for PM instructions on ordinary work, send
permission requests for delegated choices, or treat review as approval by default.

## Project contract

Read [CONTRIBUTING.md](CONTRIBUTING.md) for coordination, evidence, review, and integration rules. [DESIGN.md](DESIGN.md) owns game requirements and open choices. The user explicitly delegates routine reversible design/technical decisions toward the demo: choose from the documented goals, record assumptions, and keep moving without repeated approval cards. Do not turn an experimental default into permanent canon. A runnable experimental opening and headless/network/save fixtures now exist; no production engine is selected. [README.md](README.md) links the launcher, controls and explicit prototype limits.

Current priorities: a controlled physical character with proximity-restricted construction, and fixed/stationary contraptions/subfactories before mobile-factory expansion. Camera position is not construction authority. Godot use is accepted; record engine/API behavior, adapter limitations and probe shortcuts in the [constraint register](docs/engineering/godot-constraints.md), never silently as game requirements. Follow the [continuing research contract](docs/research/README.md) for factory/engineering-puzzle studies: deduplicate per game/coverage, close thorough game leaves, keep the recurring pipeline open.

The user requires a native implementation path. Do not add or expand Python
project code, test harnesses or operations tools. Use C++ or Rust for replacements
and new authoritative rules; the first owned toolchain is the existing C++ compiler.
Keep existing mandatory checks active until independently reviewed replacements
take over. Assess pending Python additions against this direction before landing.
The current GDScript demo and Godot adapters are transitional, not a permanent
authority choice. See the [native migration contract](docs/engineering/native-migration.md).

The dependency plan is [ROADMAP.md](ROADMAP.md), rooted at `factory-yau`; use `br ready --type task --json` to find executable next outcomes, not just organizational epics. The original progenitor owns continuing integration/design-fidelity review under [PROJECT_MANAGER.md](PROJECT_MANAGER.md), Bead `factory-wj6.3`. Proposal completion is not user approval; delegated choices, runtime evidence, integration review and production adoption are distinct. Do not leave ordinary prototype work blocked on an approval the user has delegated. Actual user play cannot be fabricated, but waiting for it need not stop other development.

Before starting, inspect Git status, ready/in-progress Beads, related closed work, and recent relevant commits. Claim a bounded task with a distinct actor name; comment the intended scope, worktree/branch, dependencies, and acceptance evidence. Do not take an occupied task or edit another agent's checkout without an agreed handoff. Spawn agents only when authorized. Keep decisions and resumable handoffs in Beads/Git/docs, not solely in chat or ignored `.notes/`.

Existing workers own continuing workstream queues, not just the last dispatched task. The user explicitly authorizes them to discover, create, refine and claim bounded follow-up tasks toward the demo without per-task PM permission. Search for duplicates, prioritize playable improvements and actual consumer evidence, record scope/dependencies before edits, and coordinate interfaces and independent reviews directly with peers. Freezing a candidate for review freezes those bytes, not its author: continue useful non-overlapping work in another linked worktree. Do not self-approve or treat a pending prerequisite as satisfied. Escalate genuine authority/resource conflicts, not routine reversible choices. The progenitor retains design-fidelity review and serialized main integration/publication, and corrects course through Bead details and review rejections rather than micromanagement.

This is initially the only test machine. Use `python3 -B scripts/run_local.py check|heavy|benchmark -- <command>` for cooperating work: shared cheap checks, one heavy lane, exclusive measurements. Initial supported-tool parallelism is eight jobs; heavy/measurement admission requires 20 GiB free disk and 8 GiB available memory. Do not override floors without a documented resource decision, nest wrappers, unlink live locks, or delete unrelated artifacts. These are operational settings, not game performance targets or complete host isolation. See [resource admission](docs/engineering/local-resources.md).

## Issue tracking

Use **Rust Beads (`br`)** for project task tracking. This repository uses SQLite and JSONL, not the Go `bd` CLI or Dolt.

```bash
br ready --json
br show <id>
br create --title "Task title" --type task --priority 2
br update <id> --claim
br close <id>
br sync --flush-only
```

Issue IDs use the `factory-` prefix. Read `br robot-docs` for command guidance. **All of `.beads` is private and Git-ignored**, including JSONL exports and configuration, not just the database. Never force-add it. Back up the portable text export separately to the user-authorized unlisted gist; keep its identifier and account telemetry out of public source. An unlisted gist is accessible to anyone with its URL, not access-controlled private storage.

## Mandatory shared Beads directory for worktrees

The main checkout owns the canonical `.beads` directory. **Every linked Git worktree MUST have a `.beads` directory symlink pointing to that same canonical directory. All worktrees share one database and one issue namespace.**

- Never run `br init` in a linked worktree or create a separate worktree database.
- After creating any worktree, run the main checkout's `scripts/link-beads-worktree.sh` before using Beads there.
- Verify that `.beads` is a symlink and that `br where` resolves to the main checkout's directory.
- Never replace an existing worktree database without reconciling its issues. The helper refuses databases and locally modified snapshots and archives clean checked-out metadata before linking.
- Do not stage the `.beads` symlink, metadata or exports from any checkout. Export/backup from the canonical tracker; stage source changes explicitly in the relevant worktree.

Run these from the main checkout, substituting a branch and worktree path:

```bash
git worktree add -b feature/example ../factory-example
./scripts/link-beads-worktree.sh ../factory-example
```

This sharing policy applies to every agent and every worktree, including temporary review or test worktrees.

Legacy branches may still track `.beads`. Do not merge/rebase them across its removal while the shared symlink is attached: the current clean-worktree policy does not make that historical transition safe. Preserve their commits and hand source-only changes to the integration owner for a fresh current-main worktree. Never force, stash or unlink the shared tracker to advance an old branch.

## Session completion

1. Update the relevant Beads issues, record evidence/limits and independent review for substantial changes, and close only when acceptance is satisfied.
2. Run `br sync --flush-only` to persist the private portable export. The progenitor owns separate backup freshness; no ledger content belongs in source commits.
3. Run `python3 -B scripts/run_local.py check -- python3 -B scripts/check.py`; review and explicitly stage only scoped source paths.
4. Run `python3 -B scripts/check_commit.py` before committing. This top-level staged coordinator and the installed precommit hook acquire one check permit for non-GDScript changes or one heavy permit for staged GDScript compilation. Do not wrap either command or `git commit` itself, or nest admission. Install the local hook using `./scripts/install-hooks.sh`; never auto-stage fixes or bypass a failure as acceptance evidence. Changes to safety gates need independent review.
5. The integration owner serializes main landing and publication. Validate branches against current main before landing; a clean textual merge is insufficient.
6. Inspect `git status` and hand off any remaining work or verification limits.

The user authorized the public remote `https://github.com/dan-garvey/factory_project`. The progenitor owns reviewed-main publication; do not push private ledger/history, account data or unreviewed work branches. Historical Beads removal was explicitly authorized before the first push, with original history retained locally. Rust Beads does not run Git commits or pushes for you.
