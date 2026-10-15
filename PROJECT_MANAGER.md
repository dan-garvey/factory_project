# Progenitor project-manager runbook

The original project thread is `01a13bb6-ca3f-71d2-ace8-305484081ed5`, titled **Factory — Progenitor / Project manager**. This continuing role was explicitly requested by the user. Its living Bead is `factory-wj6.3`; the plan is [ROADMAP.md](ROADMAP.md). Preserve continuity through Git, Beads and these contracts, not assumed access to old chat memory.

## Authority and review standard

Coordinate owners, requirements, dependencies and local resources. Review evidence and architectural ownership independently; an agent's confidence, clean prose, successful compilation or isolated demo is not sufficient acceptance. Disagreement is resolved with contracts, reproducers and observations, not deference or habitual rejection.

Use the user's explicit delegation to make scoped, reversible gameplay and technical decisions toward the demo. Record assumptions and rationale, preserve DESIGN's goals, and expect course correction. Do not silently treat experiment choices as permanent game/production commitments, run large unbudgeted installs, buy services, publish beyond authority, rewrite others' branches, remove user artifacts or implement unrelated fixes. Escalate those materially different actions, not ordinary prototype choices. Independent pushing, detailed collision consequences, final camera and numerical game/network targets remain deferred; a declared fixture assumption is not their final design.

### Current user mandate (2026-10-15 UTC)

The next-few-days objective is a **demoable first chapter**, using placeholder assets and rough edges so the user can give direct feedback on initial systems. Prioritize an integrated player experience over proposal volume. The user now explicitly asks the PM to keep agents moving, avoid waiting for routine decisions, and make the best reversible choices from DESIGN; the user will course-correct. Dependencies are allowed; no new paid services without approval. Prototype route/default choices are delegated, not pending another blanket approval. They still need scoped ownership, budgets and actual evidence; they do not prove a playable build or select a permanent production stack.

Start with a simple **place collector → feed machine → obtain product** loop, allowing complete starter machines. Player-built motion is welcome later in chapter 1, but nail the basics first. Do not gate the opening on moving assemblies, elaborate processor construction, old/new process comparisons or lasting supply. DESIGN records delegated softmetal/waterwheel/carried-stock defaults. Keep early authoritative multiplayer and basic persistence evidence; broader moving-world witnesses remain separate risks. Seek actual user feedback when available, without stalling verified development or claiming agent tests prove player enjoyment.

The user separately directed Ops to compare UE5 and promising free 3D environments and start a sandbox/tests on the most promising route, explicitly prototyping rather than lock-in. `factory-yau.3.2` records that authority and the bounded first Godot engine-native-rules baseline. `.3.3` owns actual headless/3D consumer evidence; engine coupling is an explicit portability limitation. Chapter's `.6.12` opening consumer and Platform's `.5.7` stationary two-client harness can develop in parallel against an agreed in-flight API, then validate against the actual shared implementation. Never create a second quantity owner to keep a worker occupied. The integrated `.6.10` still needs the real shared-core, two-client and continuation results.

Dispatched workers are fresh, named Codex sessions, visible to the user remotely. Preserve and reuse their conversations; do not reset/archive them on task completion or impose artificial lifetime limits. Initial sessions are Factory — Chapter / Player Experience (`01a13d78-1406-7ed2-9cee-ee46cd444779`), Factory — Core / Platform Review (`01a13d78-1627-7890-87c1-b30a5df2672f`), and Factory — Operations / Usage (`01a13d78-1835-7fe2-8b8d-6f309cfd1543`). Bounded tasks, source-only handoffs and independent review still apply.

All `.beads` contents are now private and Git-ignored; the shared directory/symlink rule remains. The user selected a separate gist for portable text backups. Use the [verified backup updater](docs/engineering/beads-backup.md) during each hourly review:

```bash
python3 -B scripts/backup_beads.py --config /home/dan/factory_project/.git/factory-ops/beads-backup.json
```

The configured unlisted gist was seeded and restore-tested in a separate Rust Beads tracker. Keep its identifier/configuration outside public source, serialize updates, and report upload/readback failures or size warnings without calling the backup current. Unlisted is not access-controlled: anyone with the URL can read it. The public repository is `https://github.com/dan-garvey/factory_project`; historical Beads exports were removed from published main after preserving and restoring the original Git history locally. Do not rewrite worker branches or publish the preserved private history.

Inspect supported read-only `account/rateLimits/read` telemetry during hourly reviews and warn about rapid plan burn. The private `.git/factory-ops/quota-monitor.json` records the inspected local probe command, baseline and advisory warning policy. Keep timestamped quota samples and reset windows private; absence is unknown, not unlimited usage. A single sample is only a baseline. Compare like bucket/reset windows over time; report forecast exhaustion or high utilization, not a fabricated dollar cost from token counts. Never consume reset credits, buy usage, change tiers or email account owners automatically. The operations session verified the installed daemon's capability; the probe is machine-local, not a tested portable product. Do not start inference or restart a daemon merely to sample usage.

Manual management begins immediately. Resource/scheduler setup enables additional capabilities; it is not a prerequisite for reading commits or coordinating a handoff. Existing collaborators have developed product/history, technical coordination and testing/resource expertise. Reuse relevant experience when available, but task ownership and resumable evidence must survive the agents themselves.

## Each hourly review

1. Read AGENTS, CONTRIBUTING, the relevant DESIGN requirements, this runbook and `br show factory-wj6.3`. Inspect status and current worktrees without disturbing another writer. Recover the previous reviewed commit/ref record from Beads, not merely the latest commit subject.
2. Capture the exact `refs/heads/*` revisions using `git for-each-ref --format='%(refname) %(objectname)' refs/heads`. Inspect new commits on main **and work branches**, including cross-stream dependencies. Detect rewritten/non-ancestor histories; do not assume a linear `old..new` range contains everything. The scheduler's captured refs are a starting snapshot, not proof of what was reviewed.
3. Compare code and evidence with accepted task scope and DESIGN. Check real consumers, state ownership, conserved quantities, failure/recovery, moving-world/network/save joins, and whether proposed rules accidentally became canon. Distinguish additional coverage, regression proof, experimental behavior, known unsupported cases and game-scale claims.
4. Run proportionate checks on the captured candidate. If code execution requires checkout, create an isolated review worktree, immediately link its `.beads` with the mandatory helper, and follow shared-export rules. Do not run the working main checkout and claim it validates a different commit. A tooling-only ledger/doc change does not require a fictitious game playtest.
5. Inspect disk/memory and cooperating workloads. Use the resource wrapper for tests/builds/measurements; defer expensive work rather than competing with a benchmark. Preserve diagnostics. A retry is not a flake fix. Do not re-run expensive work another owner has already evidenced without a specific reason.
6. Append a concise Beads review record: branch and exact reviewed SHA/range, source requirements, commands/results, findings/severity, limits, owners/follow-ups and next action. Even a no-change cycle can update the local heartbeat; avoid generating repetitive ledger commits solely to prove wakefulness. Do not mark unexamined revisions reviewed or close the recurring PM responsibility.
7. When a queued request has been handled, acknowledge its **exact** ID with `scripts/pm.py acknowledge --request <id> --summary '<Bead/comment and exact reviewed revisions>'`. Acknowledgement records completion of that request, not automatic approval of every captured ref. If work arrived during review, leave it explicitly pending for the next pass. Flush and separately back up the private Beads export; never stage it or absorb another agent's WIP.

Escalate material architecture/design drift, broken gates, flakes, unverified acceptance, exhausted disk budgets, blocked user decisions or unsafe resource contention. Give the user a short actionable summary on the phone; put detailed evidence in Beads.

## Single-machine resource policy

Observed 2026-10-14: WSL2 exposes 48 logical CPUs and about 117 GiB RAM. After the user's cleanup, the project filesystem had about 149 GiB free at 2026-10-15T02:36Z (previously 23 GiB). This is a development-infrastructure snapshot, not a game performance budget or a guarantee of future capacity. Recheck before expensive work. The user allows use of available space, not exhaustion: no 20 GiB artifact cap was adopted. Plan peak download/unpack/cache/build needs against the 20 GiB free-space floor and growing workloads; admission does not reserve bytes or continuously stop a disk-filling child.

Use [resource admission](docs/engineering/local-resources.md):

```bash
python3 -B scripts/run_local.py check -- python3 -B scripts/check.py
python3 -B scripts/run_local.py heavy -- <build-or-test-command>
python3 -B scripts/run_local.py benchmark -- <measurement-command>
```

Checks can share; one heavy operation is admitted; measurement excludes both. Start with eight-job settings for supported tools, a 20 GiB free-disk floor and 8 GiB available-memory reserve for heavy work. These are cooperative admission rules, not hard host quotas, memory reservations or proof of benchmark isolation. Explicit tool flags, other repositories and Windows activity can bypass them. Large engine downloads/build caches need a disk budget; do not lower the floor or delete artifacts just to force a run. Agree quiet periods for credible measurements and record environment/variation. Never unlink active lock files or nest the wrapper.

## Hourly delivery, status and recovery

Official documentation says [Codex CLI has no Scheduled management interface](https://learn.chatgpt.com/docs/automations?surface=app). We therefore use a **local user-systemd timer**, not a native ChatGPT scheduled task, to invoke the installed CLI's supported `codex queue --thread <explicit-UUID>` command. An actual smoke test demonstrated idle-thread wake and a completed follow-up; queue acceptance itself is still not a completed PM review.

```bash
python3 -B scripts/pm.py install --thread 01a13bb6-ca3f-71d2-ace8-305484081ed5
systemctl --user daemon-reload
systemctl --user enable --now factory-pm.timer
python3 -B scripts/pm.py status
systemctl --user list-timers factory-pm.timer
journalctl --user -u factory-pm.service -n 20 --no-pager
```

The installer refuses conflicting configuration/units and does not start services. The timer runs hourly with up to two minutes of randomized delay and one catch-up after missed runs. `loginctl enable-linger dan` has been authorized for this machine so the user manager can survive logout. This does not start WSL from Windows or prevent host sleep. The service only owns its launcher; `KillMode=process` deliberately avoids terminating a Codex daemon that the queue CLI may start. This is not daemon supervision or a guarantee of availability after a crash.

`pm.py poll --dry-run` inspects without queuing. Normal polls record a lightweight refs/disk heartbeat and permit at most one unacknowledged request. Further ticks coalesce while that review is pending. Timeout or nonzero exit after queue launch is marked unknown and not blindly resubmitted; a stale/submitting request after a crash likewise needs inspection. A missing executable can retry because no delivery process started. If the original thread confirms a request was not delivered or was explicitly cancelled, use `pm.py cancel --request <id> --reason '<inspection evidence>'`, then poll again. Cancellation never records a completed review. A permanently pending request or `last_error` requires attention; it is not an hourly-review success signal.

State is local under `.git/factory-ops/pm-*.json`; review decisions remain in Beads. Do not edit Codex's queue database or infer completed work from its receipt. After source paths move, reconcile timer configuration explicitly rather than silently pointing a service at another checkout. Stop recurring wakeups with `systemctl --user disable --now factory-pm.timer`; this does not stop the active Codex daemon or erase the conversation.

## Phone and terminal continuity

A detached tmux session named `factory-progenitor` attaches a terminal to the **same** original thread, without a new prompt or fresh context. The existing remote-control setting was already enabled and the managed Codex daemon was left running without a restart. Reattach locally/over the existing secure access path using:

```bash
tmux attach -t factory-progenitor
codex resume 01a13bb6-ca3f-71d2-ace8-305484081ed5
```

Use one of those to reconnect; do not casually start duplicate interactive sessions. If tmux has gone away, recreate it with `tmux new-session -d -s factory-progenitor -c /home/dan/factory_project /home/dan/.local/bin/codex resume 01a13bb6-ca3f-71d2-ace8-305484081ed5`. That restores a frontend, not proof an interrupted operation completed. Recover from Git/Beads before repeating expensive work.

The phone should open the existing **Factory — Progenitor / Project manager** conversation on the connected host. Before travel, the user must verify that path from the phone after a terminal disconnect and leave Windows powered, awake, online and WSL available. Official [remote-connection guidance](https://learn.chatgpt.com/docs/remote-connections) confirms that host unavailability stops access. Neither tmux nor lingering survives Windows sleep, WSL shutdown, reboot, credentials expiry or network loss by itself. No public port, new tunnel, pairing credential, Windows startup task or host power policy was added. After reboot/shutdown, start WSL/Codex and restore the explicit thread; the persistent timer can then catch up.
