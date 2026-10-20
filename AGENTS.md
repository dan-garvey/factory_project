# Agent Instructions

## Communication

Write complete sentences with normal word spacing in chat, Beads, notes and
handoffs. Concise does not mean compressed. Keep identifiers separate from the
surrounding prose and explain unfamiliar abbreviations.

Keep routine coordination and publication results in the owning Bead. Do not send
the progenitor routine ready-to-land messages, review receipts or acknowledgements.
Notify them only for a material cross-stream finding, an unresolved resource or
ownership conflict, or a decision outside delegated authority.
Use a short outcome, what it means, the next action and one task/comment reference.
Put detailed hashes, commands, counters and resource tables in structured evidence;
do not forward those records verbatim into the user's conversation.

Beads MUST contain new, material information only. Repetitive comments, notes,
descriptions and status updates are forbidden. Never post an update whose result
is "nothing has changed": no unchanged-condition restatements, duplicate evidence
or approval summaries, repeated blocker notices, heartbeat comments or receipts
that merely confirm an existing record. Link the original once when needed for a
new finding or decision. Record a new result, finding, decision, ownership change
or actionable handoff concisely; otherwise say nothing. Prune redundant history
while preserving distinct findings, actual test results and their evidence.

Use these instructions as the writing standard, not old messages or session logs.
Rewrite or remove malformed prose from agent-facing records rather than preserving
it as a quoted example, an appended correction or a duplicate archive. Retain the
necessary technical facts in clear language. Do not erase or relabel actual test
results, and never turn a wording cleanup into a passing test.

## Self-management and review

Agents own their work queues and coordinate tasks, dependencies, reviews and local
resources directly. The progenitor reviews landed work against DESIGN.md and files
concrete fix Beads, rather than assembling or approving every landing. Course
corrections belong in specific Bead details and review findings, with a concrete reason
and acceptance condition. Do not wait for PM instructions on ordinary work, send
permission requests for delegated choices, or treat review as approval by default.

The current user-directed trial decentralizes landing. Each workstream owner
builds, tests and commits their scoped code, resolves its current-main joins, and
lands and publishes it without waiting for the progenitor or pre-merge review.
Independent review may happen after merge. A completed relevant review already
counts; do not require another reviewer, PM sign-off, plan, source-freeze, receipt
or other approval chain. Reuse passing checks and reviews for unchanged relevant
inputs. Never bypass the installed hook, hide a failed check or ignore a known
correctness finding merely because review is asynchronous.

Keep concurrent workstreams narrow and non-overlapping. Agree shared interfaces
directly and coordinate edits to shared files rather than creating competing
implementations or rewriting another author's branch. Prefer merging current main
into an owned branch over heavy rebasing. Only the brief canonical-main update and
push are mechanically serialized through the shared Git lock documented in
CONTRIBUTING.md; build, test and review outside it. There is no human landing queue.

Never hand off work you could complete yourself, including ordinary integration
and publication. If another owner must take over, state the concrete constraint
and remaining action. Respect user authorization, privacy, desktop ownership and
actual resource limits; these remain operating constraints, not approval tiers.
This trial supersedes older progenitor-only landing and pre-merge-review prose,
including copies in older worktrees. It does not change gameplay requirements.

## Playtesting

Agent-controlled desktop playtests are disabled until the user explicitly
re-enables them. Use human playtesting for gameplay and usability feedback. Do not
queue or execute agent desktop tests, their availability probes or game launches,
or perform foreground acquisition, activation, input or capture for those tests.
This suspension supersedes prior standing playtest authorization and pending
requests. Preserve existing evidence and verdicts without replay. Ordinary
automated checks and development continue; human playtesting is not an additional
code-landing approval gate. The suspended workflow is recorded in
`factory-yau.6.46`.

## Project contract

Read [CONTRIBUTING.md](CONTRIBUTING.md) for coordination, evidence, review, and integration rules. [DESIGN.md](DESIGN.md) owns game requirements and open choices. The user explicitly delegates routine reversible design/technical decisions toward the demo: choose from the documented goals, record assumptions, and keep moving without repeated approval cards. Do not turn an experimental default into permanent canon. A runnable experimental opening and headless/network/save fixtures now exist; no production engine is selected. [README.md](README.md) links the launcher, controls and explicit prototype limits.

Current priorities: a controlled physical character with proximity-restricted construction, and fixed/stationary contraptions/subfactories before mobile-factory expansion. Camera position is not construction authority. Godot use is accepted; record engine/API behavior, adapter limitations and probe shortcuts in the [constraint register](docs/engineering/godot-constraints.md), never silently as game requirements. Follow the [continuing research contract](docs/research/README.md) for factory/engineering-puzzle studies: deduplicate per game/coverage, close thorough game leaves, keep the recurring pipeline open.

The user requires a native implementation path. Do not add or expand Python
project code, test harnesses or operations tools. Use C++ or Rust for replacements
and new authoritative rules; the first owned toolchain is the existing C++ compiler.
Keep existing mandatory checks active until validated replacements preserve their
contracts; independent review follows the same asynchronous policy. Assess
pending Python additions against this direction before landing.
The current GDScript demo and Godot adapters are transitional, not a permanent
authority choice. See the [native migration contract](docs/engineering/native-migration.md).

The dependency plan is [ROADMAP.md](ROADMAP.md), rooted at `factory-yau`; use `br ready --type task --json` to find executable next outcomes, not just organizational epics. Workstream owners integrate their own changes; the progenitor focuses on post-merge quality and design-fidelity review toward the demo-completion goal. The hourly PM schedule and its runbook remain retired. Cadence maintenance belongs to `factory-cadence` under `factory-wj6.21`, not another source-approval gate. Proposal completion is not user approval; delegated choices, runtime evidence, review and production adoption are distinct. Do not leave ordinary prototype work blocked on an approval the user has delegated. Actual user play cannot be fabricated, but waiting for it need not stop other development.

Before starting, inspect Git status, ready/in-progress Beads, related closed work, and recent relevant commits. Claim a bounded task with a distinct actor name; comment the intended scope, worktree/branch, dependencies, and acceptance evidence. Do not take an occupied task or edit another agent's checkout without an agreed handoff. Spawn agents only when authorized. Keep decisions and resumable handoffs in Beads/Git/docs, not solely in chat or ignored `.notes/`.

Existing workers own continuing workstream queues, not just the last dispatched task. The user explicitly authorizes them to discover, create, refine and claim bounded follow-up tasks toward the demo without per-task PM permission. Search for duplicates, prioritize playable improvements and actual consumer evidence, record scope/dependencies before edits, and coordinate interfaces directly with peers. Keep already-reviewed bytes and evidence attributable to their original revisions, but do not wait for review or progenitor publication to land checked work. Author checks are not independent review, and a pending implementation prerequisite is not satisfied by a proposal. Escalate genuine authority/resource conflicts, not routine reversible choices. The progenitor corrects landed work through actionable Bead findings rather than micromanagement or another approval gate.

This is initially the only test machine. Use the installed native `factory-local --root CHECKOUT check|heavy|benchmark -- <command>` for cooperating work: shared cheap checks, four concurrent heavy slots, and exclusive measurements. Its executable is `<common-git-dir>/factory-local-resources/factory-local`. Existing `python3 -B scripts/run_local.py` commands and commit hooks remain supported through a compatible exclusive legacy gate; they can temporarily reduce concurrency. Supported-tool parallelism is eight jobs per admitted command; heavy/measurement admission requires 20 GiB free disk and 8 GiB available memory. Do not override floors without a documented resource decision, nest wrappers, unlink live locks, or delete unrelated artifacts. These are operational settings, not game performance targets or complete host isolation. See [resource admission](docs/engineering/local-resources.md).

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

Legacy branches may still track `.beads`. Do not merge/rebase them across its removal while the shared symlink is attached: the current clean-worktree policy does not make that historical transition safe. Preserve their commits and transfer only scoped source changes into your own fresh current-main worktree. Never force, stash or unlink the shared tracker to advance an old branch.

## Session completion

1. Update the owning Bead with new results, verification limits and the actual landed commit. Close implementation work when its declared outcome is satisfied; post-merge review and any concrete fix Beads are separate, not a hidden landing or closure approval.
2. Run `br sync --flush-only` to persist the private portable export. The progenitor owns separate backup freshness; no ledger content belongs in source commits.
3. Run focused checks needed to validate the changed behavior, then review and explicitly stage only scoped source paths. Do not duplicate the commit hook's full suite on unchanged relevant inputs.
4. Commit through the installed precommit hook, which invokes `python3 -B scripts/check_commit.py` as the single mandatory staged check. Do not run the same coordinator manually before the hook on unchanged inputs; a manual run is optional diagnostics. The coordinator acquires one check permit for non-GDScript changes or one heavy permit for staged GDScript compilation. Do not wrap the coordinator or `git commit` itself, or nest admission. Install the local hook using `./scripts/install-hooks.sh`; never auto-stage fixes or bypass a failure as acceptance evidence. Changes to safety gates preserve their validation contracts and receive independent review under the same asynchronous policy, not an extra landing approval.
5. Land and publish your checked scoped branch using CONTRIBUTING.md's short shared Git transaction. Resolve conflicts and validate affected joins in your own worktree first; do not hold the landing lock during checks or reviews. A clean textual merge alone is insufficient.
6. Inspect `git status` and hand off any remaining work or verification limits.

The user authorized the public remote `https://github.com/dan-garvey/factory_project`. Workstream owners may publish their checked changes to existing main under this trial; no progenitor handoff is required. Do not push private ledger/history, account data or work branches under this authority, or change the remote. Historical Beads removal was explicitly authorized before the first push, with original history retained locally. Rust Beads does not run Git commits or pushes for you.
