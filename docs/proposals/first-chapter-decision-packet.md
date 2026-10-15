# First-chapter decision packet

Status: revised 2026-10-15 UTC after the user's scope clarification. The basic
opening shape and basics-first order below are accepted; concrete content and
the chapter extension remain proposals. [DESIGN.md](../../DESIGN.md) owns game
requirements. There is no runtime or selected engine yet.

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
basic-loop feedback. The wider new-process/new-product/scaling relationship
remains important to progression; it need not all appear in the first demo.

## Decisions still open

Ask only for choices needed by the next stage, rather than one approval of an
entire hypothetical chapter:

- **Opening content:** the collector, one input, one process, and its product.
  A simple familiar transformation is a candidate, not an adopted recipe.
- **Minimal operating rules:** how the collector and processor are supplied and
  powered, their physical ports, and how the player places and retrieves stock.
  No unlimited construction stock, remote withdrawal, or particular toolbox
  policy is approved by the scope correction.
- **Session objective and stock:** what the player is asked to make and whether
  a disclosed finite test fixture suffices for this demo. Ordinary inventory
  confirmation is the existing starting preference; consumption, delivery,
  and multiplayer credit rules are still open if the demo exercises them.
- **Reversible implementation environment:** permission and budget for a named
  trial remain distinct from eventual production-stack adoption. This gameplay
  clarification selects neither an engine nor a language.

Full team/story progression, lasting-supply engineering, dispatch, alternate
process comparisons, and an elaborate construction-access network do not have
to be implemented merely to try this opening. Unimplemented systems must be
absent or clearly disclosed, not silently simulated by an invented game rule.

## Earlier proposals: useful later inputs, not opening requirements

The earlier packet recommended softmetal press A → channel-roll B → kit C plus
a player-built carrier. Its assertion that a motionless opening could not count
as a first-chapter experience was an agent inference, now superseded by the
user's clarification. The old carrier-versus-reduced-probe choice is obsolete;
the accompanying stock/toolbox/check defaults were not approved.

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
Provide a small inspectable explanation and observe an actual user session.
Record confusion and friction before committing to a more elaborate chapter.

**Broader technical and chapter evidence:** retain the
[common witness](prototype-witness.md) for rotary/gantry/train-like motion,
actual player/collision joins, moving harvest/transfers, authority/correction,
exact-count recovery, and moving save/rejoin. These stay early architecture
risks and production-adoption evidence, not prerequisites for first feedback on
the stationary loop. Test every later feature through its integrated consumers;
a green opening cannot stand in for a moving-world witness.

The [candidate trial](candidate-trial-packet.md) and
[save/resume contract](save-resume-contract.md) remain proposals/contracts with
their own permission and evidence boundaries. The implementation plan has a
separate basic-demo/feedback path before later chapter expansion; see
[ROADMAP.md](../../ROADMAP.md) and the private Beads ledger. No game runtime,
playtest, performance, or delivery-date evidence is established by this paper.
