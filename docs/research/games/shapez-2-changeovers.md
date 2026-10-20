# shapez 2: programmable changeovers and retained work

Status: **independently reviewed partial source study**. Study Bead: `factory-yau.8.9`.
Owner: Recovery. Primary texts checked 2026-10-15 UTC; retained text hashes and
continuity rechecked 2026-10-19 UTC.

Scope: six dated developer accounts of wires, programmable production, target
distribution, inspection and teaching between June 2024 and the April 2026
1.0 announcement. Two original candidate puzzles are developed below. Exact
current-build Make Anything Machine algorithms, transition timing, scheduling,
save behavior and balance remain unverified. No actual game play was performed.

The reviewed [spatial and logistics survey](shapez-2.md) covers support, fragile
finishing, routing, capacity and first-wrong-handoff diagnosis. This follow-up
examines changing the requested work and distributing configuration. It does
not repeat those five cards or extend their acceptance to programmable systems.

## Evidence and chronology

These are primary developer descriptions, with the dates attached to the
claims. An announcement establishes what was described at that time; it does
not establish every implementation detail or the behavior of a later build.

| Source | Declared evidence | Limit |
| --- | --- | --- |
| [Devlog 023, 2024-06-13](https://steamcommunity.com/games/2162800/announcements/detail/4149584538797983677) | Programmable Make Anything Machines were already being built. The early wire system had update-order problems, weak port feedback and manually entered targets. | Historical early-access limitations; not evidence of present defects or a current requirement to enter every target manually. |
| [Update 0.0.9, 2024-12-12](https://steamcommunity.com/games/2162800/announcements/detail/4469355336712587322) | The Gameplay section reports stable wire signals while off-screen. The bug-fix list separately names simulation-precision issues, wire-simulation behavior and filters dropping items during rapid signal changes. | A dated developer announcement, not independent execution or a current timing/changeover specification. The filter fix identifies a historical material-preservation problem; it does not prove global determinism. |
| [Dimension update, 2025-06-02](https://steamcommunity.com/games/2162800/announcements/detail/526468444896364471) | Separates global transmitter channel selection from its carried signal; adds an Operator Shape Receiver and wire-signal hover inspection. | No complete rule for target replacement, in-flight work or signal latching is given. |
| [Community manager Q&A, 2026-01-15](https://steamcommunity.com/games/2162800/announcements/detail/17584622977155734) | Discusses the difficulty of naturally teaching sophisticated wire logic and a possible tutorial video. | A development intention, not a final inventory of available teaching. |
| [Visual changes devlog, 2026-02-19](https://steamcommunity.com/games/2162800/announcements/detail/517487250982831176) | Describes improving the visual separation and readability of wire buildings. | Visual design intent does not establish control timing or correctness. |
| [1.0 announcement, 2026-04-23](https://steamcommunity.com/games/2162800/announcements/detail/518618855026721216) | Reports an expanded Codex with Wires and Make Anything Machine tutorials and example blueprints; also extends global transmitter channel types. | This later shipped teaching claim supersedes using the January discussion to imply that tutorials are absent. The Codex pages themselves have not been inspected here. |

The progression visible in these accounts is from manually supplied programmable
targets toward dedicated target input, more flexible distribution and better
inspection. That is useful evidence for a new decision: how a reusable factory
changes jobs while retaining responsibility for work already admitted. The
sources leave its exact implementation open, so the rules in the following
cards are **original proposed experiments**, not descriptions of shapez 2.

## Pattern shapez2-control-01: Finish admitted work before changing its tool

**Goal and setup.** A stationary press serves two products using different die
settings. Start with one press, a removable die carrier, a short input queue and
finite blanks. An upstream request changes while a blank is held at the tool.
The challenge is to deliver the requested products without losing a blank,
silently reclassifying work or requiring a person to empty the line every time.
The exact die, latch and request mechanisms would need their own rules before
implementation.

**Player verbs.** Arrange the queue and holders, change the die setting, isolate
the feeder from the press, route finished work, and inspect the selected job and
the piece physically held. A simple introductory version allows a manual
changeover; the deeper version asks the player to automate the same operations.

**Constraints.** Each blank has one physical holder. A requested new setting
does not retroactively finish or replace an admitted piece. The press needs
working clearance to adjust its tooling. Finite stock and limited space make
throwing away all old work or duplicating every machine costly. These are
candidate constraints for this experiment, with no recipe or campaign policy
selected by this note.

**Solution families.** Drain the line before admitting the new job: simple and
easy to inspect, with an interruption at each switch. Hold a pending setting
until the active piece exits: more compact continuous work, with a meaningful
need to distinguish selected and active settings. Build parallel dedicated
presses and select their feed: larger and more expensive, with simpler local
tooling. Retaining old work in a marked side queue can reduce disruption, but
requires a complete return path and a way to apply the correct setting later.

**Appeal, as design inference.** The request arrives faster than the physical
work can change. A useful solution makes that mismatch understandable through
the mechanism: a visible carrier, isolated feeder and waiting blank give the
player something concrete to redesign. The intended reward is a reusable
factory that changes product, rather than a larger output counter.

**Failure and recovery.** A premature adjustment should produce a visible stall
under a declared invalid-processing rule. Keep the held blank and identify its
old setting. The player can complete that work, return it to a compatible queue,
or explicitly dismantle an empty section under the normal custody rules. A
reset that clears the queue would destroy the decision. Requiring repeated
manual emptying would leave recurring upkeep in the supposed automation.

**Teaching and progression.** First expose one manual, stopped changeover with
one visible blank. Next add a second queued blank, then request changes while
the line runs. An automated pending-setting mechanism belongs to later
expressive controls. The initial stationary chapter can establish visible
holders, safe stopping and stock-preserving recovery before that mechanism is
considered.

**Mechanical 3D adaptation.** A fixed press with an accessible die carrier and
an independently isolated feed is a candidate. Its local tool adjustment may
move internally; the factory remains stationary. A mechanically selected stop
or cam is one possible control form. Electricity stays excluded by
[DESIGN](../../../DESIGN.md), and this note selects no universal control medium.

**Engineering risks.** Persist the active setting, pending request, actual held
piece and queue order across a partial changeover. Define which event commits a
setting before testing multiplayer races. Acknowledging a request cannot itself
prove that the tool has physically adjusted. Existing build proximity and part
delivery remain separate concerns. An unattended solution still depends on a
complete feed and output path; renewable inputs alone would not supply them.

**Falsifier and smallest experiment.** Use a two-setting press with three finite
blanks. Change the request at each holder boundary, including during a stopped
partial cycle; save and continue at the same cuts. Check that every blank still
has one holder and the active setting is intelligible. Compare drain-first,
pending-setting and parallel solutions. Defer the idea if one extra generic
buffer removes every decision, if adjustments need repeated intervention, or if
players cannot determine which setting applies to held work.

**Sources and related cards.** Programmability and later target input are
described in the [2024 devlog](https://steamcommunity.com/games/2162800/announcements/detail/4149584538797983677)
and [Dimension update](https://steamcommunity.com/games/2162800/announcements/detail/526468444896364471).
The historical [rapid-switch filter fix](https://steamcommunity.com/games/2162800/announcements/detail/4469355336712587322)
motivates checking material preservation; it does not supply this press's rules.
Related `shapez2-02` concerns when to finish a fragile part, and `shapez2-05`
concerns diagnosing a wrong handoff. This card adds active versus pending job
state during a reusable machine's changeover.

**Disposition:** deferred candidate. It needs a worthwhile local tooling rule
and later controls; it must not displace the physical stationary opening.

## Pattern shapez2-control-02: Address the work request without moving its stock

**Goal and setup.** Three fixed work cells share a request selector. Each has a
different physical feed and tool arrangement. Send a new job to the intended
cell while another cell finishes existing work. A compact way to distribute
configuration is useful only if material routing and local machine readiness
remain meaningful.

**Player verbs.** Connect control paths, select a destination and requested
setting, isolate a branch, arrange local feed and output, and inspect what each
cell has received and physically begun. The eventual physical form of addressed
control is open. The source game's global channels are an analogy for separating
destination from content, not a selected construction capability here.

**Constraints.** A control request carries no material or construction parts.
An addressed cell still requires its real stock, power, local clearance and
compatible tooling. Two simultaneous conflicting requests need a declared,
observable outcome. A destination must be distinguishable from the current
setting value; changing one must not silently lend another cell its resources
or complete its work.

**Solution families.** Dedicated control links are spatially explicit and easy
to trace, but need more routes as the factory grows. An addressed shared path
can reuse a route at the cost of selectors, isolation and harder diagnosis.
Local fixed programs with a coarse enable signal reduce message complexity,
while committing more machinery to each product family. A shared setting
distributed to every cell is cheap for identical work; it becomes unsuitable
when cells must finish different jobs independently.

**Appeal, as design inference.** This turns expansion into a choice about which
couplings to share. Geometry can make a dedicated link attractive for a nearby
cell and a shared route useful across several floors. Correctness stays visible
at the individual work cell instead of disappearing into a global production
toggle.

**Failure and recovery.** Show the destination, requested setting and local
active setting separately. A wrong destination can be isolated and corrected
without deleting its stored work. Missing stock should remain a local supply
problem. A request conflict should not cause a half-applied setting in one cell
and a contradictory success indication elsewhere. Once solved, normal changes
need to proceed without repeated player relabelling or resetting.

**Teaching and progression.** Begin with two dedicated, inspectable links and
one setting per cell. Introduce destination selection only after the player can
trace a request to a local mechanism. Then add a third cell or another floor,
with one cell still busy. This adds independent control of a subfactory, a new
capability rather than a required speed upgrade.

**Mechanical 3D adaptation.** A later fixed workshop might distribute an encoded
mechanical selection to local selectors, with visible isolation at each branch.
No electrical wires are proposed. The medium, cost, signal range and physical
decoding rules need separate design. Construction at a distant cell continues
to require its own permitted reach and delivered parts.

**Engineering risks.** Save destination bindings, local active jobs, pending
changes and real holders together. Define behavior when a cell is removed or
rebuilt; a new machine should not silently inherit an old request just because
it occupies the same position. Multiplayer participants' shared physical effects
and individual progression remain a separate open policy. Visibility or camera
distance must not determine whether configured machinery keeps operating.

**Falsifier and smallest experiment.** Route two settings to three small fixed
cells with deliberately different supply. Change destination while one cell is
busy, remove an idle destination, and continue from a saved partial setup. Reject
the shared-path variant if it merely adds address-entry chores, if dedicated
links always dominate without a tradeoff, or if its abstraction erases the
physical supply and access decisions that make the factory interesting.

**Sources and related cards.** The [Dimension update](https://steamcommunity.com/games/2162800/announcements/detail/526468444896364471)
explicitly separates channel identity and signal, and adds signal inspection.
The [1.0 announcement](https://steamcommunity.com/games/2162800/announcements/detail/518618855026721216)
extends channel types. These establish the source analogy, with exact switching
semantics still unverified. `shapez2-03` covers physical route crossing;
`shapez2-05` supplies the shared first-wrong-handoff diagnostic pattern.

**Disposition:** deferred candidate for later expressive controls. It requires a
useful physical control medium and does not authorize global material access.

## Synthesis and open coverage

The two decisions are distinct: completing admitted work under a changing job,
and distributing a job to the intended subfactory. Inspection is essential to
both. A third card about identifying the first wrong output would duplicate
`shapez2-05`; off-screen stability is an engineering invariant rather than an
additional puzzle by itself. Neither is counted as new pattern coverage here.

Teaching needs gradual tasks as well as reference material. The January 2026
discussion and April Codex announcement can coexist: an advanced control system
can receive documentation without becoming part of every ordinary first factory.
This is a design inference, with no claim about players' actual experience of
those tutorials. Their content needs examination before making that assessment.

## Coverage and review ledger

- Covered so far: dated progression of programmable target input, channel/content
  separation, inspection, the historical filter-loss fix and changing teaching
  claims; two original stationary mechanical candidate cards.
- Open: representative actual target changes and retained-work behavior in a
  declared build; exact timing/latching and conflict semantics; Codex content;
  a genuinely distinct further puzzle before broader coverage is claimed.
- Independent review: Chapter accepted the frozen partial note `2733f8a` on
  2026-10-19 UTC. Root reviewed its source attribution, chronology, duplicate
  patterns and mechanical adaptation. The 0.0.9 row keeps its explicit historical
  Gameplay report separate from the bug-fix entries. This is not runtime acceptance.
- Validation and final revision: recorded with the frozen handoff in the study
  task. This note is catalogued only as partial source research, not adopted mechanics.
- Closure: this partial leaf remains open. `factory-yau.8` remains ongoing.
- Next work: seek precise primary documentation or an attributed demonstration
  of a programmable changeover, while physical-character/reach work preempts.
