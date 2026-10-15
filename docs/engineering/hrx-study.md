# Lessons from HRX's agent-assisted workflow

Research snapshot: 2026-10-14 America/Chicago (2026-10-15 UTC), public `ROCm/hrx-system` at [`e32033b778176f1d918e3209365df3e4039268c3`](https://github.com/ROCm/hrx-system/tree/e32033b778176f1d918e3209365df3e4039268c3). Three parallel researchers examined testing/build tooling, commit/PR history, and coordination. They inspected source and a varied 12-change sample, including corrections, rejected work, and a revert. They did not build HRX or reproduce its numerical/performance claims. Detailed findings and links are retained in the research Beads under the workflow epic.

## What is testimony, and what is public evidence?

In the supplied conversation, Ben describes 20–30 persistent specialized agents, a shared Rust Beads database symlinked across worktrees, learning through other agents' work, private notes, remote build infrastructure, strict gates, and owner-led architectural review. This is valuable firsthand workflow testimony, not something Git history alone proves. Claims about agent ownership or social behavior likewise remain his observations, not established internal states.

The public contributor contract does explicitly describe concurrent workstreams and self-contained submissions. But HRX ignores its private `.beads`, `.notes`, and agent overrides; public commits do not expose their contents or prove the staffing, symlink topology, learning mechanism, or causal effect on velocity. Some sampled merged PRs have no visible peer review, and an accidental unreviewed merge was reverted. This is evidence of specific practices and corrections, not universal compliance. [Contributor contract](https://github.com/ROCm/hrx-system/blob/e32033b778176f1d918e3209365df3e4039268c3/CONTRIBUTING.md), [ignore policy](https://github.com/ROCm/hrx-system/blob/e32033b778176f1d918e3209365df3e4039268c3/.gitignore), [revert #423](https://github.com/ROCm/hrx-system/pull/423#issuecomment-5415861197).

## The transferable habits

### 1. Make claims reviewable without the authoring session

Submissions must identify a problem and impact, concrete evidence, scope/design intent, verified results, and relevant performance/size costs. Agent assistance does not lower that bar. A maintainer can replace an implementation while preserving its discovery and testing the original reproducer. The #1380/#1377 overlap became an explicit contribution policy in #1385. [Contract](https://github.com/ROCm/hrx-system/blob/e32033b778176f1d918e3209365df3e4039268c3/CONTRIBUTING.md), [original reproducer #1380](https://github.com/ROCm/hrx-system/pull/1380), [policy #1385](https://github.com/ROCm/hrx-system/pull/1385).

Factory adaptation: Beads holds concise evidence and handoffs; accepted contracts live in the design/engineering docs and reasons survive in Git. Preserve reproducers and credit when work is superseded. Private notes help exploration but are not the canonical decision record.

### 2. Test the real boundary, with a discriminating witness

The variant-HTTP flake fix waits for registration retirement, not the earlier withdrawal from discovery. Its regression holds compiler completion open, checks intermediate behavior, then releases it and checks destruction/name reuse without timing sleeps. Another change replaces broad integer snapshots with executable scenarios and independent scalar oracles. [Retirement correction `7497634b`](https://github.com/ROCm/hrx-system/commit/7497634baba4d9b575272630e79d1f0fdffc4e57), [oracle change `00a5207c`](https://github.com/ROCm/hrx-system/commit/00a5207cd84fa42381ffa6299e0cb750872fcc8c).

A test added in #805 explicitly passes on both baseline and candidate: ordinary coverage, not proof that it catches the repaired defect. #1696 separates successful numerical cases, remaining arithmetic failures, unsupported cases, binary-size costs, and benchmark limits. [Coverage limitation](https://github.com/ROCm/hrx-system/commit/1459844eb0988997d97fe1357ea222564498d099), [numeric evidence #1696](https://github.com/ROCm/hrx-system/pull/1696).

Factory adaptation: exercise actual consumers and invariants; retain old failure evidence when feasible. Do not relabel compilation, coverage, retries, or noisy measurements as stronger evidence. Current executable coverage concerns repository tooling only.

### 3. Review architectural ownership independently of passing demos

#1714 was rejected despite useful numerical and lifecycle demonstrations because channel-owned execution bypassed the queue's scheduling, memory transitions, and retirement responsibilities. The rejection preserved independent fixes and test scenarios without preserving the proposed API. #143 separately demanded a production consumer: adding a timestamp API did not establish that the shipping event-timing path used it. [Ownership rejection](https://github.com/ROCm/hrx-system/pull/1714#issuecomment-6178029378), [consumer review](https://github.com/ROCm/hrx-system/pull/143#discussion_r3654659141).

Factory adaptation: ask which layer owns a rule/state transition, who consumes the interface, and what end-to-end behavior changes. A portability layer or impressive simulation demo does not establish appropriate boundaries. Keep engine and multiplayer architecture decisions open until tested against representative game needs.

### 4. Clean merges and confident prose do not establish readiness

#143 obtained architectural approval but was still blocked because current main had removed a representation the branch referenced. #805 review counted 1,666 complete scans; the follow-up computed immutable demand once. These are concrete integration/cost checks, not confidence inferred from commit style. [Integration condition](https://github.com/ROCm/hrx-system/pull/143#pullrequestreview-4833422308), [scan review](https://github.com/ROCm/hrx-system/pull/805#discussion_r4067500705), [follow-up](https://github.com/ROCm/hrx-system/commit/467e793f492659b1ad6c37728a8357ec97274072).

Factory adaptation: validate the integrated candidate against current main. Commit messages should retain the final reason, scope, evidence, and limits, not private session references or obsolete exploratory designs. Human-readable history serves later review and bisection; message polish is not evidence of correct code or agent authorship.

### 5. Guardrails protect the work, not just a green badge

HRX routes source and package development through explicit `dev.py` lanes. Its precommit hook requests the paranoid staged profile. Staged-fixer safeguards reject partial staging and stop when fixes alter the candidate; a regression exercises the actual Git index. A separate worktree-scoped source lock was introduced after concurrent mutation/truncation failures. [Router contract](https://github.com/ROCm/hrx-system/blob/e32033b778176f1d918e3209365df3e4039268c3/CONTRIBUTING.md), [hook](https://github.com/ROCm/hrx-system/blob/e32033b778176f1d918e3209365df3e4039268c3/lefthook.yml), [staged correction `9c5d118b`](https://github.com/ROCm/hrx-system/commit/9c5d118b628b418c779cf49cf503dc3799109973), [source lock `782476ff`](https://github.com/ROCm/hrx-system/commit/782476ff9427573738997ec8284cb0c053038fa8).

Factory adaptation: one non-mutating check entrypoint, real filesystem/index safety tests, one writer per worktree, and a staged-candidate hook that never absorbs unrelated edits. We do not yet need mutating formatter orchestration or a lock service. Bugs found during review should become narrowly useful automated checks where possible.

### 6. Keep test scope and resource isolation explicit

Affected-test selection uses Bazel's configured dependency graph rather than a parallel guessed graph. CI divides infrastructure, product, sanitizer, hardware, and installed-package validation; some hardware lanes are optional. The public files do not prove every test or hardware lane is mandatory for every commit. [Graph correction `46f9a9ea`](https://github.com/ROCm/hrx-system/commit/46f9a9ea093e44753fcd3635c17ac188fb2417e3), [product CI](https://github.com/ROCm/hrx-system/blob/e32033b778176f1d918e3209365df3e4039268c3/.github/workflows/ci_iree.yml).

NativeLink's public configuration offers optional local cross-worktree caching and bounded execution, explicitly acknowledging cold-build overhead. It is not proof of the remote fleet described in conversation. GPU test serialization is local to an invocation; cross-job exclusivity belongs to the runner. Benchmark lease tokens alone do not establish an idle/healthy host. [Cache guide](https://github.com/ROCm/hrx-system/blob/e32033b778176f1d918e3209365df3e4039268c3/build_tools/nativelink/README.md), [resource boundary](https://github.com/ROCm/hrx-system/blob/e32033b778176f1d918e3209365df3e4039268c3/build_tools/bazel/test_resources.bzl), [measurement contract](https://github.com/ROCm/hrx-system/blob/e32033b778176f1d918e3209365df3e4039268c3/libamdf/cts/gpu/linux/io_uring/README.md).

Factory adaptation: run the entire small current tooling suite, name exactly what it covers, and coordinate expensive measurements explicitly. Add graph selection, caches, hardware matrices, remote execution, and benchmark admission only after measured need. A fast helper test suite is not evidence of a game performance target.

## What we are adopting now

- One shared Rust Beads database across linked worktrees, as requested; Factory continues versioning its portable JSONL export, unlike HRX's private-ledger policy.
- Bounded ownership, dependency-aware workstreams, searchable evidence, explicit handoffs, and independent review of substantial changes.
- A concise contributor contract and readable final-design commit history.
- A non-mutating local check command and staged precommit gate, tested against real disposable Git fixtures. No remote or CI enforcement is claimed.

We are not importing Bazel/CMake, HRX's full hook stack, custom lint rules without failure witnesses, remote build infrastructure, an agent dashboard, or a 20–30-agent staffing target. The game implementation stack remains unchosen. The useful invariant is that accepted work leaves evidence and makes subsequent work safer—not that our directory tree resembles HRX's.
