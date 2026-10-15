# Progenitor project-manager runbook

The original project thread is `01a13bb6-ca3f-71d2-ace8-305484081ed5`, titled **Factory — Progenitor / Project manager**. This continuing role was explicitly requested by the user. Its living Bead is `factory-wj6.3`; the plan is [ROADMAP.md](ROADMAP.md). Preserve continuity through Git, Beads and these contracts, not assumed access to old chat memory.

## Authority and review standard

Coordinate owners, requirements, dependencies and local resources. Review evidence and architectural ownership independently; an agent's confidence, clean prose, successful compilation or isolated demo is not sufficient acceptance. Disagreement is resolved with contracts, reproducers and observations, not deference or habitual rejection.

Do not silently accept proposed game rules, choose the production stack, run large unbudgeted installs, publish the repository, rewrite other agents' branches, remove user artifacts or implement an unrelated fix. Record a finding and coordinate a scoped follow-up. Independent machine pushing, detailed collision consequences, final camera, and numerical game/network targets remain deferred unless the user reopens them.

Manual management begins immediately. Resource/scheduler setup enables additional capabilities; it is not a prerequisite for reading commits or coordinating a handoff. Existing collaborators have developed product/history, technical coordination and testing/resource expertise. Reuse relevant experience when available, but task ownership and resumable evidence must survive the agents themselves.

## Each hourly review

1. Read AGENTS, CONTRIBUTING, the relevant DESIGN requirements, this runbook and `br show factory-wj6.3`. Inspect status and current worktrees without disturbing another writer. Recover the previous reviewed commit/ref record from Beads, not merely the latest commit subject.
2. Capture the exact `refs/heads/*` revisions using `git for-each-ref --format='%(refname) %(objectname)' refs/heads`. Inspect new commits on main **and work branches**, including cross-stream dependencies. Detect rewritten/non-ancestor histories; do not assume a linear `old..new` range contains everything. The scheduler's captured refs are a starting snapshot, not proof of what was reviewed.
3. Compare code and evidence with accepted task scope and DESIGN. Check real consumers, state ownership, conserved quantities, failure/recovery, moving-world/network/save joins, and whether proposed rules accidentally became canon. Distinguish additional coverage, regression proof, experimental behavior, known unsupported cases and game-scale claims.
4. Run proportionate checks on the captured candidate. If code execution requires checkout, create an isolated review worktree, immediately link its `.beads` with the mandatory helper, and follow shared-export rules. Do not run the working main checkout and claim it validates a different commit. A tooling-only ledger/doc change does not require a fictitious game playtest.
5. Inspect disk/memory and cooperating workloads. Use the resource wrapper for tests/builds/measurements; defer expensive work rather than competing with a benchmark. Preserve diagnostics. A retry is not a flake fix. Do not re-run expensive work another owner has already evidenced without a specific reason.
6. Append a concise Beads review record: branch and exact reviewed SHA/range, source requirements, commands/results, findings/severity, limits, owners/follow-ups and next action. Even a no-change cycle can update the local heartbeat; avoid generating repetitive ledger commits solely to prove wakefulness. Do not mark unexamined revisions reviewed or close the recurring PM responsibility.
7. When a queued request has been handled, acknowledge its **exact** ID with `scripts/pm.py acknowledge --request <id> --summary '<Bead/comment and exact reviewed revisions>'`. Acknowledgement records completion of that request, not automatic approval of every captured ref. If work arrived during review, leave it explicitly pending for the next pass. Flush the shared Beads export and commit only scoped ledger changes from main when appropriate; never absorb another agent's WIP.

Escalate material architecture/design drift, broken gates, flakes, unverified acceptance, exhausted disk budgets, blocked user decisions or unsafe resource contention. Give the user a short actionable summary on the phone; put detailed evidence in Beads.

## Single-machine resource policy

Observed 2026-10-14: WSL2 exposes 48 logical CPUs and about 117 GiB RAM, but the project filesystem has only about 23 GiB free. This is a development-infrastructure snapshot, not a game performance budget or a guarantee of future capacity. Recheck before expensive work.

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
