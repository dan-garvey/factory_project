# Agent instructions

## Work and records

- [DESIGN.md](DESIGN.md) owns accepted game requirements. [README.md](README.md)
  gives the current entrypoints. Beads owns tasks, dependencies, proposals,
  decisions, investigations and review results; Git retains historical source.
- Use Rust Beads (`br`), not `bd` or Dolt. Before work, inspect Git status,
  recent relevant commits, ready/in-progress tasks and related closed work.
  Claim a bounded task with a distinct actor and record scope, checkout/branch,
  dependencies and intended evidence. Never take occupied work without a handoff.
- Owners may discover and complete follow-ups toward the playable demo.
  Routine reversible choices are delegated; record assumptions and keep moving.
  Do not turn a prototype default into permanent design. Spawn agents only when
  authorized. Coordinate shared files and interfaces through the owning Bead.
- Use Beads for agent coordination, naming affected owners. Do not send direct
  peer-session notifications. Record only new material findings, decisions,
  ownership changes and results, not heartbeats, receipts or repeated blockers.
- Write complete sentences with normal spacing. Keep user updates brief; put
  detailed evidence in its owning record. Correct malformed prose in place,
  preserving actual results and their limits.
- Never create new Markdown files unless the user explicitly requests one;
  this includes plans, reports and research notes. Put task-specific
  findings in Beads and reusable guidance in existing documents. Shorten or
  remove obsolete prose instead of appending supersession notices. A local
  defect normally needs a fix/test and Bead finding, not a new global instruction.
- Research belongs in existing per-game Beads under `factory-yau.8`. Search
  completed coverage before repeating a study; close thorough leaves while
  leaving the continuing pipeline open. Research does not adopt mechanics.

## Shared tracker and checkouts

All `.beads` content is private and Git-ignored, including exports and settings.
Never stage it or publish account data. Every linked worktree must symlink the
main checkout's canonical directory; never initialize a second tracker there.

From the main checkout:

```bash
git worktree add -b feature/example ../factory-example
./scripts/link-beads-worktree.sh ../factory-example
```

Verify the symlink and `br where` before using Beads. Do not overwrite an existing
worktree database. Legacy branches that tracked `.beads` require transferring
scoped source changes into a fresh current-main worktree, not a merge/rebase
across tracker removal with the shared symlink attached.

```bash
br ready --type task --json
br show <id>
br update <id> --claim --actor <name>
br close <id>
br sync --flush-only
```

The integration owner maintains the separate authorized unlisted-gist
[backup](docs/engineering/beads-backup.md); its identifier stays private.

## Implementation and verification

- Prefer fast iteration; remove superseded behavior and compatibility code
  unless the user requires it. Use C++ or Rust for new implementation. Do not
  add or expand Python project code, tests or operations tools. Existing checks
  remain active until validated replacements preserve their contracts.
- Keep one native authority. Godot presentation/input must not own a shadow
  simulation. Record current engine/adapter constraints in the compact
  [register](docs/engineering/godot-constraints.md), separately from game rules.
- Use icons, direct manipulation and spatial grouping; text buttons are a last
  resort. Provide tooltips, keyboard focus descriptions and keyboard routes.
- Use [resource admission](docs/engineering/local-resources.md) for checks,
  builds and measurements. Never nest wrappers, unlink live locks, delete
  active files or lower floors without a documented resource decision. Follow
  that document's artifact lifecycle: Beads references do not require permanent
  retention of generated files, screenshots or incompatible development saves.
- Run relevant consumer checks and the installed hook. Reuse passing checks
  for unchanged inputs. Never bypass a failure, auto-stage fixes or turn a
  rerun into a fix. Distinguish source, native, rendered, performance and human
  play evidence; retain exact revisions and material limitations.
- Desktop control is disabled until the user re-enables it. Do not focus
  windows or inject input. Launching and passive screenshots/video are allowed.
  Label agent graphical launches with `--test-purpose=TEXT` through the tracked
  agent launcher so the purpose appears in the OS window title. Add title
  initialization before opening a new graphical fixture target.
  Inspect relevant pixels, recording revision, view and conditions. Capture
  visible changes in their surrounding worksite or interface so shape, scale,
  orientation, connections and interaction cues can be judged together.
  Passive fixtures do not prove usability.

## Finish, publish and review

Owners test, commit, reconcile current main and publish their scoped work.
Follow the [build/hook and landing recipes](docs/engineering/native-builds.md).
Keep concurrent writers in separate linked worktrees. Merge current main into
committed work rather than routinely rebasing; never overwrite another checkout.
Only the short main update/push holds the shared Git lock.

Write commit messages that explain what changed and why it matters to the game
at its current stage of development, using specific context rather than canned
repetitions.

For every authored commit, including merges, open an unassigned `review-request`
Bead naming the exact commit, implementing agent, scope and checks. Never review
your own commit or claim your own request. After opening one, claim and complete
an available other-author review before returning to your task. Fix concrete
findings in your own checkout, validate and publish them, and request review of
each fix. Scale review effort to the changed risk: inspect the relevant contract,
affected consumer and evidence. For editorial-only prose, check claims, links and
consistency; reuse passing checks for unchanged inputs.

If a commit changes anything visible, its `review-request` Bead must include a
retained screenshot of the change in its surrounding worksite or interface,
with the source revision, view and conditions. An isolated part or widget image
alone is insufficient. Reviewers also judge the complete player-facing result:
proportions, neighboring parts, connection and interaction cues, and the action
the player is trying to take, alongside the usual diff, contract and consumer
checks. State what passive images cannot establish about ordinary or human use.

For a disjoint preservation merge, verify both parents, relevant path and blob
identity, unchanged test inputs and absence of changed interfaces or combined
behavior. Record that proof in its review request and reuse the original checks
and review evidence, including a contextual screenshot for unchanged visual
inputs. Changed interfaces, conflict resolutions or combined behavior
need focused integration checks. Record a concrete verdict and evidence limits.
Existing relevant review counts; review is not a pre-merge approval gate.

Record the actual landed revision and new results once, close satisfied work,
flush Beads, and inspect Git status. Remaining implementation and human-play
gaps stay explicit. The progenitor reviews design fidelity and files actionable
fixes; there is no PM landing queue or hourly approval schedule.

Only checked existing `main` publication to
`https://github.com/dan-garvey/factory_project` is authorized. Do not publish
private tracker history, work branches, credentials or account data, or change
the remote under that authority.
