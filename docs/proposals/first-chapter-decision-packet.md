# First-chapter decision packet

Status: revised 2026-10-15 UTC after basics-first staging and delegated decisions.
The basic shape/order and revisable opening defaults are recorded in
[DESIGN.md](../../DESIGN.md). The wider chapter extension remains to be scoped.
No playable chapter or production-engine acceptance is established here.

## Start with a working production loop

The first playable can be this simple:

1. Place a resource collector.
2. Feed its output through physical transport into a machine.
3. Let the machine process it and retrieve the product.

Complete, single-placement starter machines are acceptable here. The player does
not have to assemble a complicated processor, moving factory, rotary carrier, or
gantry before this counts as a valid opening. The user's resource A / machine B /
product C notation describes this one chain, **not** the older three-product
progression proposal.

The immediate aim is feedback on moving around and building in a small 3D site,
placement and connections, readable material flow, processing, and retrieval.
Use placeholder assets and a small relevant visual explanation. Test actual
authoritative quantities and output handling, not just animated items. Specific
power, input, capacity, and blocked-output behavior must be declared before
implementation; the simple scope does not itself select those rules.

## Player-built motion can come later in chapter 1

The user welcomes player-built motion as a later part of the same chapter:
**nail the basics first**, then introduce a bounded construction problem. Do not
interpret this as either a requirement to finish motion before first feedback
or a decision to exclude motion from chapter 1.

One possible extension is a functional tool head with player-built transmission,
feed, and a fixed-cycle rotary or gantry arrangement. Select the project after
basic-loop validation, using user feedback when available without waiting for it.
The wider new-process/new-product/scaling relationship
remains important to progression; it need not all appear in the first demo.

## Reversible opening defaults are delegated

The user asks agents and the PM to make the best reversible choices from DESIGN,
keep implementation moving, and allow course correction. Do not repeat routine
approval cards. Use the [opening defaults](../../DESIGN.md#delegated-defaults-for-the-basic-opening-demo):

- A finite softmetal collector, physical belt and complete press make plates.
- Simple waterwheel/shaft power and physically carried construction parts.
- Retained held work under blocked output/power pauses; exact item accounting.
- A small explanation and non-consuming four-plate inventory goal; no campaign
  or technology credit is implied by provisional two-client fixture access.

Counts, timings and content are tunable demo choices, not permanent balance.
The environment owner may select and run a bounded reversible sandbox; an
engine-native Godot rules baseline is the first route, not a production choice
or proof of engine-independent mechanics. Keep budgets, source review and real
runtime evidence; delegation is not evidence that a feature works.

Full team/story progression, lasting-supply engineering, dispatch, alternate
process comparisons, and an elaborate construction-access network do not have
to be implemented merely to try this opening. Unimplemented systems must be
absent or clearly disclosed, not silently simulated by an invented game rule.

## Earlier proposals: useful later inputs, not opening requirements

The earlier packet recommended softmetal press A → channel-roll B → kit C plus
a player-built carrier. Its assertion that a motionless opening could not count
as a first-chapter experience was an agent inference, now superseded by the
user's clarification. The old carrier-versus-reduced-probe choice is obsolete;
the accompanying stock/toolbox/check defaults were not accepted by that earlier
scope clarification. The later delegated defaults above now govern the demo.

These source proposals remain available, not selected content:

- [Challenge](first-chapter-challenge.md) and [layouts](first-chapter-layouts.md):
  new products, old/new process comparisons, rotary/gantry geometry, and feed,
  support, dwell, and clearance costs. Those costs still matter if chosen later;
  do not hide them in an ostensibly simple tool head.
- [Walkthrough](chapter-walkthrough.md): later build/diagnose/recover/expand and
  phase-retaining restart observations, not a mandatory first-session syllabus.
- [Supply](chapter-supply.md): a proposed finite-to-lasting source transition,
  exploration/base alternatives, and depletion safeguards. The deep-flow premise
  and protected reserve are unapproved; lasting supply is not an opening gate.
- [Construction supply](construction-supply.md): alternatives for reducing
  errands while preserving physical stock location; no default is selected.

## Evidence in two stages

**Opening:** exercise the real place → connect → collect → process → retrieve
path. Check quantities through actual consumers, retain work when output is
blocked, and document accepted operating/failure rules. Keep single-player on
the server's authoritative rules, exercise a minimal stationary two-client path,
and check basic partial-production save/continuation in the integrated demo.
Provide a small inspectable explanation and obtain an actual user session when
available. Record confusion and friction; do not stall verified development
waiting for user availability or call agent tests evidence of player enjoyment.

**Broader technical and chapter evidence:** retain the
[common witness](prototype-witness.md) for rotary/gantry/train-like motion,
actual player/collision joins, moving harvest/transfers, authority/correction,
exact-count recovery, and moving save/rejoin. These stay early architecture
risks and production-adoption evidence, not prerequisites for first feedback on
the stationary loop. Test every later feature through its integrated consumers;
a green opening cannot stand in for a moving-world witness.

The historical direct-C [candidate trial](candidate-trial-packet.md) is not the
selected first baseline. The [save/resume contract](save-resume-contract.md)
retains its evidence boundaries. The implementation plan separates the basic
demo and continuing scoped development from actual user feedback; see
[ROADMAP.md](../../ROADMAP.md) and the private Beads ledger. No game runtime,
playtest, performance, or delivery-date evidence is established by this paper.
