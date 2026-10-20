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

### Autonomous workstream queues

Workers may choose, create, refine and claim their next bounded task without a PM dispatch. Own an ongoing queue: Platform covers authoritative rules, sessions and launch integration; Chapter covers playable experience, teaching and optional mechanical expansion; Ops covers independent consumer validation and local operation. The additional Playability worker focuses on first-run interaction/teaching, and Recovery focuses on ordinary multiplayer disruption/continuation. These are coordination defaults, not silos or overlapping file ownership: agree concrete boundaries and peer reviews directly in Beads. Reuse the existing named worker sessions; cadence maintenance belongs to `factory-cadence`. Search existing open and closed work first, explain the player benefit or concrete risk being addressed, name intended paths/contracts, and retain real prerequisite edges. Do not invent duplicate state owners or process-only work merely to appear busy.

Arrange one independent review directly and resolve concrete findings through the relevant tests and that reviewer. Share a reproducible patch and its results; a plan, source freeze or receipt does not need separate approval. The author can continue useful work in another linked worktree while review or landing proceeds. Reuse passing checks and reviews when their relevant inputs are unchanged. Never close an implementation as accepted just to unblock its review, self-approve, or bypass a failed check. If every useful next task genuinely depends on unfinished work, record the specific blocker once and coordinate with its owner; temporary idle time is then honest, not an excuse to expand scope arbitrarily.

Notify the integration owner for an exact handoff ready to land, an unexpected failure/material finding, an unresolved resource conflict, or a decision outside delegated authority. Routine task selection, scope refinement, resource coordination and peer review belong to the agents and the owning Beads, not repeated permission requests. The integration owner serializes main landing/publication and may serve as the single independent reviewer, but adds no approval gate after another independent reviewer has completed the review. Cadence maintenance corrects queue/process hangups without owning source integration. Course correction uses concrete review findings, rejections and Bead details, not routine dispatch or micromanagement. Resource admission and paid/destructive/permanent-choice limits remain unchanged.

## Durable memory and handoffs

Readable prose is a project requirement. Use complete sentences and normal
spacing, including in internal coordination. Give the outcome and next action
first; keep long evidence inventories in structured artifacts and link to them.
Do not use old status messages or session logs as writing templates. When cleaning
malformed prose, replace it in place or remove it; do not retain the old wording
beside a correction or in a new archive. Keep the underlying task and test facts
accurate and distinguish the cleanup from a change in technical acceptance.

Use the smallest appropriate record:

- Beads: task state, dependencies, observations, failed approaches, ownership, resumable handoffs.
- Git: accepted implementation and the reason for the change.
- Design/engineering documents: accepted requirements and reusable contracts, with rationale and superseded decisions where useful.
- `.notes/` in each worktree: ignored scratch notes. Other local agents may read a deliberately shared note, but it must not be the only copy of a decision, blocker, or test result.

Do not depend on access to a long chat log. Follow AGENTS' material-information-only rule: record a new result, finding, decision, ownership change or actionable handoff, never an unchanged status or duplicate summary. Link existing evidence rather than restating it. Use only the relevant fields of this compact entry:

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

### Native implementation and migration

The user has directed new implementation toward C++ or Rust. Do not add or expand
Python project implementation, including launchers, test harnesses and operations
tools. The first native increments use the installed C++ toolchain; a language
choice alone does not prove performance, portability or simulation correctness.
Godot remains accepted, with GDScript serving existing integration and presentation
while authoritative rules move into the native core. Do not create a parallel
mutable world or silently keep a second implementation as a fallback.

Existing Python-backed checks remain in use until reviewed native replacements
preserve their contracts. Running them is not permission to extend their Python
implementation. Review pending Python candidates against the new direction rather
than automatically landing them because historical evidence passed. Preserve that
evidence and its original source revision. The [migration inventory](docs/engineering/native-migration.md)
names executable follow-ups, the current authority boundary and adoption evidence.

Native builds and tests also require ordinary resource admission, bounded commands,
exact source/compiler provenance and independent review. Build outside the source
checkout, declare the build/test scope before execution and retain first failures.
Do not redirect a safety gate or replace its coverage through a documentation edit.

Prerequisites for current checks: Linux, Bash, Git, Python 3.10 or newer, and `systemd-analyze` for parsing the generated local scheduler units. Rust Beads is needed for project work, but checks do not invoke it, access the live database, queue real model work, or use the network. Scheduler tests parse disposable units without starting services.

```bash
./scripts/install-hooks.sh
git commit
```

Install the hook once per clone. Review and explicitly stage only scoped paths before committing. Run focused tests needed for changed behavior; do not duplicate the hook's suite on unchanged relevant inputs. A manual `python3 -B scripts/check_commit.py` run is optional diagnostics, not a required step before committing.

The installer sets repository-local `core.hooksPath=.githooks`, shared by linked worktrees, and refuses to overwrite a different configured hook path or disable executable default hooks. Git does not distribute local configuration automatically. The installed hook invokes `check_commit.py` as the single mandatory staged check, taking exactly one top-level permit: shared check for non-GDScript changes, heavy for staged `.gd` changes. Do not wrap that coordinator or `git commit` itself: either would nest resource admission. The hook does not auto-format or stage anything.

The cheap check runner validates Python/Bash syntax, optional agent JSON configuration, and the tooling integration tests. Missing or skipped tooling tests fail. Source checks do not need a private tracker or engine, so a clean public clone can run them. The staged command also checks diff whitespace, rejects every `.beads` path (including exports/configuration), and checks an immutable copy of the candidate index using raw Git blobs, without checkout filters or archive exclusions. Passing unstaged files cannot hide a broken staged candidate. Staging changes before admission or during the run make the commit coordinator fail. The temporary snapshot never contains private tracker data or invokes `br`.

For staged `.gd` changes, the coordinator also requires real GDScript parsing. The integration owner configures the existing verified runtime locally; no runtime is downloaded or selected through global settings. Replace these illustrative values with the absolute existing executable, its verified lowercase SHA256 and an owned external artifact directory:

```bash
git config --local factory.godotExecutable /absolute/verified/Godot_v4.7.2-stable_linux.x86_64
git config --local factory.godotSHA256 'verified-executable-sha256'
git config --local factory.godotArtifacts /absolute/owned/staged-compiler-evidence
```

Verify the installed release before pinning it, using the [environment trial](docs/engineering/engine-environment.md) provenance. The current compiler contract accepts only the separately verified `4.7.2.stable.official.ed1daf0bf`. Missing executable/configuration, a changed hash, wrong version or parse error refuses the game commit. Non-GDScript commits remain engine-free. Ordinary `check.py --staged` remains a cheap source gate for other changes and explicitly refuses staged GDScript with instructions to use the coordinator; it never starts an engine inside an existing check permit.

The compiler copies the immutable staged prototype project to an owned external session, imports it, then runs `--headless --check-only --script` on **every** staged project `.gd` file. Editor import alone missed the retained mechanics compile failure. Original input hashes, staged tree, binary/runner pins, post-import configuration hash, individual commands/logs and refusal receipts survive outside Git. The parser has a 5 minute/128 MiB allowance, 8 MiB logs and one engine at a time; sources are limited to 2 MiB/512 files/128 scripts for this small prototype. Only `experiments/engine-environment/godot` is supported; another script root or removal of the entire project needs an explicit contract update rather than a silent skip. Compilation is separate from actual rule, input, rendering, network and save/continuation evidence.

This intentionally simple snapshot gate copies the small tracked tree. It currently rejects staged symlinks and submodules, including the shared `.beads` symlink. Deliberate support for legitimate source symlinks/submodules requires extending the gate and tests first. If assets or build costs make whole-tree snapshots expensive, replace this mechanism with measured, cache-aware validation; do not blindly copy large assets on every commit. No game build, playtest, performance result, remote CI or branch protection is implied by a green tooling check or public remote. Local hooks can be bypassed; do not use a bypass as acceptance evidence.

Changes to the checker, tests, or hooks use the same single independent reviewer, who checks that the candidate does not weaken its own checks; they do not need an additional specialist approval. Keep tests in the same integration surface they protect. In a future CI setup, run the same canonical command and configure required checks deliberately rather than treating a workflow file as enforcement.

## Testing and review habits

Test observable behavior through its actual consumer. A tidy abstraction, successful compilation, screenshot, or demo is evidence only for what it exercises, not for architecture or every execution path. Review ownership/lifetime/contracts as well as outcomes.

For a defect, retain the reproducer and add a discriminating regression test where feasible: demonstrate the old failure and the corrected result. Clearly label a new test that passes on both revisions as additional coverage, not regression proof. Prefer a small independent oracle or invariant to a snapshot of the implementation's own output. Control asynchronous boundaries explicitly rather than using sleeps or retries to obtain green results.

Keep ordinary correctness tests repeatable. An unexpected flake blocks integration until understood; preserve diagnostics and assign an owner. A rerun is diagnostic evidence, not a fix. Any temporary quarantine needs an explicit decision, tracked owner, scope, risk, and re-enable condition; it cannot silently turn missing evidence into a pass.

As game code arrives, wire its real build/test commands into the entrypoint immediately. Grow tests around the first representative production path, not speculative subsystems: for example, resource accounting and stall/recovery through an actual contraption, then save/load and a minimal multiplayer interaction as those exist. The simulation/network implementation and engine remain undecided; this guide does not select determinism or rollback architecture.

For performance claims, record the baseline and candidate commits, scenario/seed, build settings, hardware/environment, warmup, repetitions, run order, and observed variation. Compare equivalent work and correctness. Keep timing runs exclusive on the measured resource and agree quiet periods in the task before starting expensive experiments. Do not call small noisy changes a win. Share one result rather than having several agents rerun the same expensive test. Add caching, execution limits, remote workers, or benchmark leases only after measured contention justifies them.

When review finds a repeatable class of failure, prefer a focused test or static rule over repeated admonitions. Give the guardrail its own failure witness and tests; avoid rules that merely enforce ceremony or mirror implementation details.

## Integration and history

One integration owner serializes landing into local `main` and the main checkout's shared Beads export. Code landing requires only relevant automated tests and one independent reviewer, as specified in AGENTS. The reviewer gets the patch, relevant contracts, evidence, and known limits—not an instruction to approve the author's reasoning. Record new findings and resolutions in the task. Do not require a second reviewer, PM sign-off, plan approval, source-freeze approval or receipt approval. A small documentation correction need not summon a new agent.

Before landing, compare the candidate with current `main` and resolve any incompatibility in the integration worktree. Reuse passing tests and review for unchanged relevant inputs; changed inputs need only the relevant tests and the same independent reviewer, not another approval tier. Textual mergeability alone is not proof of compatibility. Keep commits focused and each accepted commit buildable/checkable to the extent of the current project. Do not rewrite other agents' published/shared branches without agreement.

Use the existing readable subject convention, for example `chore: validate staged tooling before commits`. For nontrivial changes, the body should explain the problem/cause, accepted solution and boundaries, and verification/limits. Use task links when useful, but make the public change understandable without private Beads access. JSONL is now backed up separately rather than versioned. Remove obsolete exploratory narrative and chat/session links from final history. Do not copy HRX's tags or length rules just for resemblance.

Close tasks only after their acceptance evidence is satisfied; otherwise leave an honest handoff. Flush the private shared export, but never stage it. Stage source paths explicitly from the relevant worktree, inspect the candidate, commit through the installed hook once, then inspect status. Record code commits and closures in the private ledger; the progenitor maintains its separate gist backup. Do not expose gist identifiers or account-usage readings in public commits. Legacy tracked-ledger branches need a source-only handoff into a fresh current-main worktree, not a forced merge/rebase across removal of `.beads`.

The user authorized a public GitHub remote at `dan-garvey/factory_project`. The progenitor publishes reviewed main after excluding historical tracker data. This does not authorize other remote repositories, unreviewed branches/PRs, paid services or contact with upstream maintainers.
