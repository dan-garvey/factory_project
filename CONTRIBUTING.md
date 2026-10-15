# Working on Factory

The project includes an experimental 3D opening alongside game design and repository tooling. This is not a complete chapter or production-stack selection; [README.md](README.md) links runnable checks and their limits. [DESIGN.md](DESIGN.md) owns accepted game requirements and open decisions. [AGENTS.md](AGENTS.md) owns the mandatory Rust Beads/worktree rules. The [HRX study](docs/engineering/hrx-study.md) explains the evidence behind this workflow.

Our aim is useful, independently verifiable progress with a durable record. A larger agent roster, more elaborate process, or more passing checks is not itself progress.

## Start and coordinate

Read the applicable instructions and relevant design sections, inspect `git status`, then search existing work before creating a duplicate:

```bash
br ready --json
br list --status in_progress --json
br search --all "relevant phrase" --json
git log -8 --oneline
```

Use one Bead for a bounded outcome, not every shell command. Group related outcomes under an epic and use labels for workstreams rather than separate databases. Each implementation task should state the problem, acceptance evidence, non-goals, dependencies, and intended files/contracts. Discoveries can start rough; refine them before implementation.

```bash
br create --title "Observable outcome" --type task --priority 2
br dep add <task> <prerequisite>
br update <task> --claim --actor <agent-name>
br comments add <task> --author <agent-name> "Plan: scope, branch/worktree, contracts, verification."
```

`task` depends on `prerequisite` in the dependency example. Check the current assignee before claiming: do not steal an occupied task. Agree a handoff in comments, then change the assignee explicitly. A claim coordinates responsibility; it is not a filesystem lock.

Keep continuing responsibility for design/integration, focused implementation, and independent review. The user requests fresh, named, remotely observable Codex sessions for dispatched workers. Reuse those persistent conversations rather than resetting or archiving them after each task; give them bounded Beads outcomes without imposing artificial conversation-lifetime limits. Start with a small team and add parallel work only where boundaries and available resources support it. Spawn additional agents only when authorized by the user or applicable instructions. New agents read one relevant completed task/change and take a bounded first task with owner review; an existing owner can pair with them when available.

Use one linked worktree per concurrent writer. Follow the mandatory shared `.beads` symlink procedure in AGENTS before using Beads. Declare overlapping contracts early; coordinate sequencing rather than silently editing another writer's checkout. Ask the integration owner to resolve cross-cutting choices. The user owns the direction and has delegated routine reversible prototype decisions to the team: choose from DESIGN, record defaults and limits, and continue rather than waiting on routine cards. Permanent commitments, new paid services, destructive actions and publication beyond existing authority are not implied.

## Durable memory and handoffs

Use the smallest appropriate record:

- Beads: task state, dependencies, observations, failed approaches, ownership, resumable handoffs.
- Git: accepted implementation and the reason for the change.
- Design/engineering documents: accepted requirements and reusable contracts, with rationale and superseded decisions where useful.
- `.notes/` in each worktree: ignored scratch notes. Other local agents may read a deliberately shared note, but it must not be the only copy of a decision, blocker, or test result.

Do not depend on access to a long chat log. Record a meaningful transition, finding, or handoff, not every tool call. A compact ledger entry is enough:

```text
Problem/trigger:
Cause and owning contract:
Change, scope, dependencies:
Evidence: exact command, result, baseline/revision where relevant
Limits or remaining failures:
Next step / reviewer focus:
Branch/worktree and commit(s):
```

Append new findings rather than replacing another agent's record. Search closed Beads and relevant Git history when a choice or failure looks familiar. Move broadly useful lessons into the checked-in contract; keep one-off machine details in the task. If another change supersedes yours, preserve the original reproducer and attribution and verify that the replacement actually resolves it. Do not land both just to claim completion.

## Checks and local hooks

Prerequisites for current checks: Linux, Bash, Git, Python 3.10 or newer, and `systemd-analyze` for parsing the generated local scheduler units. Rust Beads is needed for project work, but checks do not invoke it, access the live database, queue real model work, or use the network. Scheduler tests parse disposable units without starting services.

```bash
./scripts/install-hooks.sh
python3 -B scripts/run_local.py check -- python3 -B scripts/check.py
python3 -B scripts/run_local.py check -- python3 -B scripts/check.py --staged
```

The installer sets repository-local `core.hooksPath=.githooks`, shared by linked worktrees, and refuses to overwrite a different configured hook path or disable executable default hooks. Install it in a fresh clone; Git does not distribute local configuration automatically. The hook acquires its own shared check permit and runs the staged command before a commit. Do not wrap `git commit` itself: that would nest resource admission. The hook does not auto-format or stage anything.

The check runner currently validates Python/Bash syntax, optional agent JSON configuration, and the tooling integration tests. Missing or skipped tooling tests fail. Source checks do not need a private tracker, so a clean public clone can run them. The staged command also checks diff whitespace, rejects every `.beads` path (including exports/configuration), and checks an immutable copy of the candidate index using raw Git blobs, without checkout filters or archive exclusions. Passing unstaged files cannot hide a broken staged candidate. Staging changes during the run make it fail. The temporary snapshot never contains private tracker data or invokes `br`.

This intentionally simple snapshot gate copies the small tracked tree. It currently rejects staged symlinks and submodules, including the shared `.beads` symlink. Deliberate support for legitimate source symlinks/submodules requires extending the gate and tests first. If assets or build costs make whole-tree snapshots expensive, replace this mechanism with measured, cache-aware validation; do not blindly copy large assets on every commit. No game build, playtest, performance result, remote CI or branch protection is implied by a green tooling check or public remote. Local hooks can be bypassed; do not use a bypass as acceptance evidence.

Changes to the checker, tests, or hooks need independent review: an arbitrary candidate can weaken its own checks. Keep tests in the same integration surface they protect. In a future CI setup, run the same canonical command and configure required checks deliberately rather than treating a workflow file as enforcement.

## Testing and review habits

Test observable behavior through its actual consumer. A tidy abstraction, successful compilation, screenshot, or demo is evidence only for what it exercises, not for architecture or every execution path. Review ownership/lifetime/contracts as well as outcomes.

For a defect, retain the reproducer and add a discriminating regression test where feasible: demonstrate the old failure and the corrected result. Clearly label a new test that passes on both revisions as additional coverage, not regression proof. Prefer a small independent oracle or invariant to a snapshot of the implementation's own output. Control asynchronous boundaries explicitly rather than using sleeps or retries to obtain green results.

Keep ordinary correctness tests repeatable. An unexpected flake blocks integration until understood; preserve diagnostics and assign an owner. A rerun is diagnostic evidence, not a fix. Any temporary quarantine needs an explicit decision, tracked owner, scope, risk, and re-enable condition; it cannot silently turn missing evidence into a pass.

As game code arrives, wire its real build/test commands into the entrypoint immediately. Grow tests around the first representative production path, not speculative subsystems: for example, resource accounting and stall/recovery through an actual contraption, then save/load and a minimal multiplayer interaction as those exist. The simulation/network implementation and engine remain undecided; this guide does not select determinism or rollback architecture.

For performance claims, record the baseline and candidate commits, scenario/seed, build settings, hardware/environment, warmup, repetitions, run order, and observed variation. Compare equivalent work and correctness. Keep timing runs exclusive on the measured resource and agree quiet periods in the task before starting expensive experiments. Do not call small noisy changes a win. Share one result rather than having several agents rerun the same expensive test. Add caching, execution limits, remote workers, or benchmark leases only after measured contention justifies them.

When review finds a repeatable class of failure, prefer a focused test or static rule over repeated admonitions. Give the guardrail its own failure witness and tests; avoid rules that merely enforce ceremony or mirror implementation details.

## Integration and history

One integration owner serializes landing into local `main` and the main checkout's shared Beads export. Reviewers get the patch, relevant contracts, evidence, and known limits—not an instruction to approve the author's reasoning. Record review findings and resolutions in the task. A small documentation correction need not summon a new agent; substantial implementation and changes to safety gates need independent review.

Before landing a branch, integrate current `main` in its worktree, resolve conflicts, and validate the resulting candidate. Textual mergeability is not proof of compatibility. Keep commits focused and each accepted commit buildable/checkable to the extent of the current project. Do not rewrite other agents' published/shared branches without agreement.

Use the existing readable subject convention, for example `chore: validate staged tooling before commits`. For nontrivial changes, the body should explain the problem/cause, accepted solution and boundaries, and verification/limits. Use task links when useful, but make the public change understandable without private Beads access. JSONL is now backed up separately rather than versioned. Remove obsolete exploratory narrative and chat/session links from final history. Do not copy HRX's tags or length rules just for resemblance.

Close tasks only after their acceptance evidence is satisfied; otherwise leave an honest handoff. Flush the private shared export, but never stage it. Stage source paths explicitly from the relevant worktree. Inspect the candidate, run the staged gate, commit, then inspect status. Record code commits and closures in the private ledger; the progenitor maintains its separate gist backup. Do not expose gist identifiers or account-usage readings in public commits. Legacy tracked-ledger branches need a source-only handoff into a fresh current-main worktree, not a forced merge/rebase across removal of `.beads`.

The user authorized a public GitHub remote at `dan-garvey/factory_project`. The progenitor publishes reviewed main after excluding historical tracker data. This does not authorize other remote repositories, unreviewed branches/PRs, paid services or contact with upstream maintainers.
