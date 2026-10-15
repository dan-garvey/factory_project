# Agent Instructions

## Project contract

Read [CONTRIBUTING.md](CONTRIBUTING.md) for coordination, evidence, review, and integration rules. [DESIGN.md](DESIGN.md) owns game requirements and open choices; do not silently turn tentative choices into commitments. This repository has no game runtime or selected engine yet.

The dependency plan is [ROADMAP.md](ROADMAP.md), rooted at `factory-yau`; use `br ready --type task --json` to find executable next outcomes, not just organizational epics. The original progenitor owns continuing integration/design-fidelity review under [PROJECT_MANAGER.md](PROJECT_MANAGER.md), Bead `factory-wj6.3`. Proposal completion is not user approval; first-playable scope, candidate trial permission, and production stack adoption have distinct gates.

Before starting, inspect Git status, ready/in-progress Beads, related closed work, and recent relevant commits. Claim a bounded task with a distinct actor name; comment the intended scope, worktree/branch, dependencies, and acceptance evidence. Do not take an occupied task or edit another agent's checkout without an agreed handoff. Spawn agents only when authorized. Keep decisions and resumable handoffs in Beads/Git/docs, not solely in chat or ignored `.notes/`.

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

Issue IDs use the `factory-` prefix. Read `br robot-docs` for command guidance. Keep the runtime database and its sidecars ignored; version the portable `.beads/issues.jsonl` export and configuration.

## Mandatory shared Beads directory for worktrees

The main checkout owns the canonical `.beads` directory. **Every linked Git worktree MUST have a `.beads` directory symlink pointing to that same canonical directory. All worktrees share one database and one issue namespace.**

- Never run `br init` in a linked worktree or create a separate worktree database.
- After creating any worktree, run the main checkout's `scripts/link-beads-worktree.sh` before using Beads there.
- Verify that `.beads` is a symlink and that `br where` resolves to the main checkout's directory.
- Never replace an existing worktree database without reconciling its issues. The helper refuses databases and locally modified snapshots and archives clean checked-out metadata before linking.
- Do not stage the `.beads` symlink or `.beads` changes from linked worktrees. Export and stage shared Beads metadata/JSONL from the main checkout; stage source changes explicitly in the relevant worktree.

Run these from the main checkout, substituting a branch and worktree path:

```bash
git worktree add -b feature/example ../factory-example
./scripts/link-beads-worktree.sh ../factory-example
```

This sharing policy applies to every agent and every worktree, including temporary review or test worktrees.

## Session completion

1. Update the relevant Beads issues, record evidence/limits and independent review for substantial changes, and close only when acceptance is satisfied.
2. Run `br sync --flush-only` to persist the portable export.
3. Run `python3 -B scripts/run_local.py check -- python3 -B scripts/check.py`; review and explicitly stage only scoped paths. From the main checkout, include the shared export when appropriate.
4. Run the resource-wrapped staged check before committing. The installed precommit hook acquires its own check permit; do not wrap `git commit` itself or nest admission. Install the local hook using `./scripts/install-hooks.sh`; never auto-stage fixes or bypass a failure as acceptance evidence. Changes to safety gates need independent review.
5. The integration owner serializes local-main landing and shared export commits. Validate branches against current main before landing; a clean textual merge is insufficient.
6. Inspect `git status` and hand off any remaining work or verification limits.

The repository currently has no Git remote. Keep work local unless the user requests remote setup or publication. Rust Beads does not run Git commits or pushes for you.
