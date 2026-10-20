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

Keep continuing responsibility for design/integration, focused implementation, and independent review. The user requests fresh, named, remotely observable Codex sessions for dispatched workers. Reuse those persistent conversations rather than resetting or archiving them after each task; give them bounded Beads outcomes without imposing artificial conversation-lifetime limits. Start with a small team and add parallel work only where boundaries and available resources support it. Spawn additional agents only when authorized by the user or applicable instructions. New agents read one relevant completed task/change and take a bounded first task; an existing owner can pair with them, and review follows the same asynchronous policy rather than becoming a new onboarding gate.

Use one linked worktree per concurrent writer. Follow the mandatory shared `.beads` symlink procedure in AGENTS before using Beads. Keep workstreams narrow and avoid overlapping source ownership; agree interfaces and sequence shared-file edits directly rather than silently editing another writer's checkout. Escalate only unresolved cross-stream conflicts or choices outside delegated authority. The user owns the direction and has delegated routine reversible prototype decisions to the team: choose from DESIGN, record defaults and limits, and continue rather than waiting on routine cards. Permanent commitments, new paid services, destructive actions and publication beyond existing authority are not implied.

### Autonomous workstream queues

Workers may choose, create, refine and claim their next bounded task without a PM dispatch. Own an ongoing queue: Platform covers authoritative rules, sessions and launch integration; Chapter covers playable experience, teaching and optional mechanical expansion; Ops covers independent consumer validation and local operation. The additional Playability worker focuses on first-run interaction/teaching, and Recovery focuses on ordinary multiplayer disruption/continuation. These are coordination defaults, not silos or overlapping file ownership: agree concrete boundaries and peer reviews directly in Beads. Reuse the existing named worker sessions; cadence maintenance belongs to `factory-cadence`. Search existing open and closed work first, explain the player benefit or concrete risk being addressed, name intended paths/contracts, and retain real prerequisite edges. Do not invent duplicate state owners or process-only work merely to appear busy.

Authors own implementation, build, relevant tests, commits, current-main conflict resolution and publication. Under the current user-directed trial, routine landing does not wait for a peer review or the progenitor. Independent review is asynchronous and may follow merge; completed relevant reviews still count. Resolve concrete findings through their owning Beads and relevant checks, not a new approval chain. Reuse passing checks and reviews when their relevant inputs are unchanged. Do not self-label author checks as independent review, hide failed checks or declare missing runtime/human evidence complete. If every useful next task genuinely depends on unfinished implementation, record the specific blocker once and coordinate with its owner; do not turn pending review into an artificial dependency.

Keep routine coordination and the actual published commit in the owning Bead. Do not send the progenitor ready-to-land notifications, repeated review receipts or acknowledgement-only messages. Notify them only for an actionable cross-stream finding, unresolved ownership/resource conflict or decision outside delegated authority. The progenitor reviews landed work against DESIGN and files specific fix Beads; they are not the main integration queue. Cadence maintenance corrects process hangups without becoming another gate. Resource admission, privacy and paid/destructive/permanent-choice limits remain unchanged.

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

Prerequisites for current checks: Linux, Bash, Git, and Python 3.10 or newer. Rust Beads is needed for project work, but checks do not invoke it, access the live database, queue real model work, or use the network. The retired hourly PM command and its scheduler tests have been removed, so these checks no longer require `systemd-analyze`.

```bash
./scripts/install-hooks.sh
git commit
```

Install the hook once per clone. Review and explicitly stage only scoped paths before committing. Run focused tests needed for changed behavior; do not duplicate the hook's suite on unchanged relevant inputs. A manual `python3 -B scripts/check_commit.py` run is optional diagnostics, not a required step before committing.

The installer sets repository-local `core.hooksPath=.githooks`, shared by linked worktrees, and refuses to overwrite a different configured hook path or disable executable default hooks. Git does not distribute local configuration automatically. The installed hook invokes `check_commit.py` as the single mandatory staged check, taking exactly one top-level permit: shared check for non-GDScript changes, heavy for staged `.gd` changes. Do not wrap that coordinator or `git commit` itself: either would nest resource admission. The hook does not auto-format or stage anything.

The cheap check runner validates Python/Bash syntax, optional agent JSON configuration, and the tooling integration tests. Missing or skipped tooling tests fail. Source checks do not need a private tracker or engine, so a clean public clone can run them. The staged command also checks diff whitespace, rejects every `.beads` path (including exports/configuration), and checks an immutable copy of the candidate index using raw Git blobs, without checkout filters or archive exclusions. Passing unstaged files cannot hide a broken staged candidate. Staging changes before admission or during the run make the commit coordinator fail. The temporary snapshot never contains private tracker data or invokes `br`.

For staged `.gd` changes, the coordinator also requires real GDScript parsing. Linked worktrees share the configured verified runtime; coordinate any necessary local setting change, rather than creating competing configuration or weakening the gate. No runtime is downloaded or selected through global settings. Replace these illustrative values with the absolute existing executable, its verified lowercase SHA256 and an owned external artifact directory:

```bash
git config --local factory.godotExecutable /absolute/verified/Godot_v4.7.2-stable_linux.x86_64
git config --local factory.godotSHA256 'verified-executable-sha256'
git config --local factory.godotArtifacts /absolute/owned/staged-compiler-evidence
```

Verify the installed release before pinning it, using the [environment trial](docs/engineering/engine-environment.md) provenance. The current compiler contract accepts only the separately verified `4.7.2.stable.official.ed1daf0bf`. Missing executable/configuration, a changed hash, wrong version or parse error refuses the game commit. Non-GDScript commits remain engine-free. Ordinary `check.py --staged` remains a cheap source gate for other changes and explicitly refuses staged GDScript with instructions to use the coordinator; it never starts an engine inside an existing check permit.

The compiler copies the immutable staged prototype project to an owned external session, imports it, then runs `--headless --check-only --script` on **every** staged project `.gd` file. Editor import alone missed the retained mechanics compile failure. Original input hashes, staged tree, binary/runner pins, post-import configuration hash, individual commands/logs and refusal receipts survive outside Git. The parser has a 5 minute/128 MiB allowance, 8 MiB logs and one engine at a time; sources are limited to 2 MiB/512 files/128 scripts for this small prototype. Only `experiments/engine-environment/godot` is supported; another script root or removal of the entire project needs an explicit contract update rather than a silent skip. Compilation is separate from actual rule, input, rendering, network and save/continuation evidence.

This intentionally simple snapshot gate copies the small tracked tree. It currently rejects staged symlinks and submodules, including the shared `.beads` symlink. Deliberate support for legitimate source symlinks/submodules requires extending the gate and tests first. If assets or build costs make whole-tree snapshots expensive, replace this mechanism with measured, cache-aware validation; do not blindly copy large assets on every commit. No game build, playtest, performance result, remote CI or branch protection is implied by a green tooling check or public remote. Local hooks can be bypassed; do not use a bypass as acceptance evidence.

Changes to the checker, tests or hooks remain subject to independent review under the asynchronous trial, without an additional specialist approval. They must preserve or explicitly validate replacement contracts, not weaken checks to obtain green results. Keep tests in the same integration surface they protect. In a future CI setup, run the same canonical command and configure required checks deliberately rather than treating a workflow file as enforcement.

## Testing and review habits

Test observable behavior through its actual consumer. A tidy abstraction, successful compilation, screenshot, or demo is evidence only for what it exercises, not for architecture or every execution path. Review ownership/lifetime/contracts as well as outcomes.

For a defect, retain the reproducer and add a discriminating regression test where feasible: demonstrate the old failure and the corrected result. Clearly label a new test that passes on both revisions as additional coverage, not regression proof. Prefer a small independent oracle or invariant to a snapshot of the implementation's own output. Control asynchronous boundaries explicitly rather than using sleeps or retries to obtain green results.

Keep ordinary correctness tests repeatable. An unexpected flake blocks integration until understood; preserve diagnostics and assign an owner. A rerun is diagnostic evidence, not a fix. Any temporary quarantine needs an explicit decision, tracked owner, scope, risk, and re-enable condition; it cannot silently turn missing evidence into a pass.

As game code arrives, wire its real build/test commands into the entrypoint immediately. Grow tests around the first representative production path, not speculative subsystems: for example, resource accounting and stall/recovery through an actual contraption, then save/load and a minimal multiplayer interaction as those exist. The simulation/network implementation and engine remain undecided; this guide does not select determinism or rollback architecture.

For performance claims, record the baseline and candidate commits, scenario/seed, build settings, hardware/environment, warmup, repetitions, run order, and observed variation. Compare equivalent work and correctness. Keep timing runs exclusive on the measured resource and agree quiet periods in the task before starting expensive experiments. Do not call small noisy changes a win. Share one result rather than having several agents rerun the same expensive test. Add caching, execution limits, remote workers, or benchmark leases only after measured contention justifies them.

When review finds a repeatable class of failure, prefer a focused test or static rule over repeated admonitions. Give the guardrail its own failure witness and tests; avoid rules that merely enforce ceremony or mirror implementation details.

## Integration and history

Each workstream owner lands and publishes their own checked work. The progenitor's
role is post-merge quality/design review and actionable fix Beads, not pre-merge
approval or routine patch assembly. This user-directed trial supersedes older
single-integrator and review-before-landing instructions. Existing reviews and
passing checks remain reusable; no second reviewer, PM sign-off, plan, freeze or
receipt approval is required.

Start from recent main and claim narrow files/contracts to avoid overlapping
workstreams. If main advances, merge the missing local/remote main changes into
your own branch instead of routinely rebasing shared work. Resolve actual
conflicts there, check affected interactions and commit through the installed hook.
Do not replay passing cases for unchanged relevant inputs or rewrite another
author's branch. A textual merge alone does not establish compatibility.

Only the short canonical-main update and push are serialized. After committing
and testing in your own linked worktree, use the same shared advisory lock for
this transaction. There is no person to ask for the lock and no landing roster:

```bash
factory_main_checkout=/home/dan/factory_project
factory_common_git=$(git rev-parse --path-format=absolute --git-common-dir)
factory_tested_commit=$(git rev-parse HEAD)
flock --timeout 30 "$factory_common_git/factory-main-landing.lock" \
  bash -c '
    set -euo pipefail
    landing_checkout=$1
    landing_commit=$2
    test "$(git -C "$landing_checkout" branch --show-current)" = main
    test -z "$(git -C "$landing_checkout" status --porcelain)"
    git -C "$landing_checkout" merge --ff-only "$landing_commit"
    git -C "$landing_checkout" push origin main
  ' factory-land "$factory_main_checkout" "$factory_tested_commit"
```

Never build, test or wait for review while holding this lock; never delete or
replace the lock file. If the lock is busy, the main checkout is dirty, main has
advanced or the push refuses, release it and reconcile in your own worktree.
Do not force, reset, stash someone else's changes or bypass a failure. A temporary
lock wait needs no Bead heartbeat. The lock prevents Git races, not development
or concurrent builds, and does not replace ordinary resource admission.

Record the actual landed revision and new results once in the owning Bead.
Post-merge review identifies the exact commit, violated contract and actionable
correction, with a reproducer or discriminating test when feasible. Authors own
fixes; a regression blocking others takes priority over expansion. Fix it or
coordinate a scoped revert promptly, preserving the original results and history.
Review findings are work to address, not a new ceremonial approval chain.

Use the existing readable subject convention, for example `chore: validate staged tooling before commits`. For nontrivial changes, the body should explain the problem/cause, accepted solution and boundaries, and verification/limits. Use task links when useful, but make the public change understandable without private Beads access. JSONL is now backed up separately rather than versioned. Remove obsolete exploratory narrative and chat/session links from final history. Do not copy HRX's tags or length rules just for resemblance.

Close tasks only after their acceptance evidence is satisfied; otherwise leave an honest handoff. Flush the private shared export, but never stage it. Stage source paths explicitly from the relevant worktree, inspect the candidate, commit through the installed hook once, then inspect status. Record code commits and closures in the private ledger; the progenitor maintains its separate gist backup. Do not expose gist identifiers or account-usage readings in public commits. Legacy tracked-ledger branches need a source-only handoff into a fresh current-main worktree, not a forced merge/rebase across removal of `.beads`.

The user authorized the public GitHub remote at `dan-garvey/factory_project` and now delegates routine checked-main publication to workstream owners. This does not authorize other remotes, work-branch/PR publication, private ledger/account data, paid services or contact with upstream maintainers. Historical tracker data stays excluded.
