# Study: SpaceChem — interfaces, coordination and teaching

Status: **partial dated source study; independently reviewed for partial publication**.
Study Bead: `factory-yau.8.5`. Owner: factory-ops. Checked 2026-10-19 UTC.
Scope: historical original-game design accounts, the official educator guide,
and present access to those sources. No executable/version is pinned. This is
not a current-build instruction reference, campaign walkthrough or play report.
No purchase, installation, game execution or first-hand player observation
occurred. The 63 Corvi expansion, ResearchNet puzzle corpus, defense missions
and late instruction/device edge cases remain outside the examined scope.

This follows the [research contract](../README.md) and
[study template](../STUDY_TEMPLATE.md). [DESIGN](../../../DESIGN.md) retains
physical proximity, stationary-first development, a mechanical technological
identity without electricity, gradual learning and eventual unattended operation.
The cards below are original proposals, not selected mechanics or copied levels.

## Evidence and source map

| ID / primary source | Material actually read | Qualification |
| --- | --- | --- |
| S1: [Official SpaceChem page](https://www.zachtronics.com/spacechem/) | About text and dated 2011/2012 archive entries | Establishes product identity and separates 63 Corvi; marketing does not specify present controls |
| S2: [Guide for Educators](https://www.zachtronics.com/images/SpaceChem%20-%20A%20Guide%20for%20Educators.pdf) | Text on PDF pages 1–2, particularly programming and chemistry limitations | Undated historical guide retrieved on the check date; its old platform/licensing statements are not current advice. Later screenshot pages are not used as inspected visual evidence |
| S3: [Zach Barth's postmortem](https://www.gamedeveloper.com/design/postmortem-zachtronics-industries-i-spacechem-i-) | 2012-06-13; complete article, especially open-ended puzzles, community features, audience, metrics, campaign length and tutorial sections | Developer's retrospective and reported player reactions, not independent population evidence or current implementation specification |
| S4: [Zachademics](https://www.zachtronics.com/zachademics/) | Introduction and SpaceChem subsection, as retrieved | Developer warns that introduction/scaffolding is needed and describes SpaceChem as difficult to learn; no educational outcome trial or current licensing recommendation inferred |
| S5: [GDC 2013 talk listing](https://gdcvault.com/play/1017983/Ahead-of-the-Curve-The) | Title, speaker, event and overview only | A discovery pointer. The talk was not watched, and no slide contents or video timestamps support these cards |

Five original public responses, resolved URLs, retrieval times, byte counts,
SHA256s and HTML text extractions are retained in the external
`spacechem-source-study-20261019/primary-source-map.json`. Sources are not
vendored into Git. A public gameplay manual was not verified; the educator
guide is not relabelled a manual. The museum's decorative Key Card was a
discovery lead, not an instruction specification. No mechanics are inferred
from unread slides or an unavailable screenshot.

### What the examined sources establish

**Sourced description:** S2 describes simultaneous instruction streams,
sequencing, loops, branching and synchronization. It distinguishes its simplified
bonding model from real chemistry and describes connecting machines into pipelines.
This supports studying coordination and decomposition, not assuming that its
exact processing, waiting or collision semantics are known.

**Historical design account:** S3 combines local manipulation with factory
networks. Barth describes designing distinct input/output challenges without a
prescribed solution, then using playtests to find duplicates and gaps. He reports
three competing optimization measures: cycles, symbols and reactors. His tutorial
diagnosis includes an unclear objective, too many actions in the smallest
solution, and a starting layout mistaken for a restriction on manipulator roles.
He also reports unreliable early telemetry and argues against placing the
hardest content before story completion. These are attributed accounts, not
current completion statistics or proof of enjoyment.

**Design inference here:** the useful object is an understandable transformation
with explicit interfaces and recoverable intermediate work. Multiple solutions
matter only when their differences survive the actual constraints. A repeating
program is not by itself proof of an unattended factory, and a pictured layout
is not evidence that a physical path is reachable or collision-free.

## How the engineering challenges develop

The examined material supports a coarse arc from local transformation to
connected production and coordination. It does not establish the exact modern
unlock order, tutorial sequence, reactor dimensions, pipeline capacities, output
matching tolerances, waiting rules, branching grammar or save behavior.

For our adaptation, begin with a complete station whose purpose and output are
visible. Add one new process for a new product, then let the player decide where
to divide work. Only later introduce shared tools or expressive coordination.
That is a proposed teaching progression consistent with DESIGN, not a claim
about SpaceChem's campaign or an adopted chapter plan.

There is no verified SpaceChem failure/recovery trace in this study. The
recovery cases below specify what a candidate in our game would need to prove.
In particular, we do not import an assumed reset-on-error, waste-disposal,
resource-refill or perfect-clock rule from the source game.

## Pattern spacechem-01: choose the intermediate between two work cells

**Goal and setup:** candidate here: a new coupling needs a formed collar and a
machined spindle. Begin with complete stationary tools and a finite set of
labelled workpieces; compare where the intermediate changes custody. This
introduces a new product/process combination, rather than only a larger quota.

**Player verbs and constraints:** approach, place and orient tools, connect
transport, inspect intermediate state, run and revise while stopped. Tool faces,
working clearance and the actual intermediate accepted by the next station are
hard constraints. Compactness and repeated use of a tool are optional incentives.
Do not require a programming editor in the introductory version.

**Solution families:** complete both operations in a spacious local cell; pass a
standard intermediate between two specialized cells; use one shared finishing
station with distinct waiting places. These trade parts and transport distance
against coupling, diagnosis and restart complexity. If every intermediate is
accepted everywhere, the partition decision disappears.

**Appeal:** inferred: the player chooses a boundary they can explain and reuse,
instead of following a named recipe for a preselected machine footprint.

**Failure, recovery and automation:** display the rejected intermediate at its
real holder, including its remaining operation. Stopped reorientation must not
consume or duplicate it. A solved line should accept the next workpiece without
the player carrying each intermediate between cells. A dedicated handoff should
not silently become infinite storage or remote inventory access.

**Teaching and 3D fit:** first expose one complete transformation. Later let a
working intermediate travel between fixed machines at different heights or
orientations, only once the relevant physical transport rule exists. Internal
motion is compatible with stationary editing; travelling factories are unnecessary.

**Engineering risk / falsifier:** the sole simulation owner must distinguish
waiting, partially worked and accepted material, including interrupted handoffs.
Reject a prototype if splitting a cell changes custody without a real transfer,
if only one boundary works for arbitrary reasons, or if a flat interchangeable
box makes spatial arrangement meaningless.

**Source and relation:** local/network decomposition is supported by S2/S3;
the coupling, workpieces and alternatives are proposals. Unlike
[DSP's repeated cells](dyson-sphere-program.md#pattern-dsp-05-repeat-a-working-cell-with-its-access-needs-intact),
the question is which *intermediate contract* makes the cell reusable, not how
to stamp a known cell. **Disposition: candidate; no experiment selected.**

## Pattern spacechem-02: distinguish waiting from a circular dependency

**Goal and setup:** later candidate: two fixed work cells share a transfer bay.
Each can retain a partially processed workpiece while waiting for the other to
release a required holder. Explain and remove the circular dependency without
discarding material. This is a proposed wait model, not an observed SpaceChem
deadlock or a claim that its input/output instructions have these semantics.

**Player verbs and constraints:** inspect holders and the next required action;
move or add a finite staging place, reorder a handoff, or separate the routes.
Every workpiece must have one actual owner. Completion must not depend on a
hidden timeout, an arbitrary wait duration or whichever client updates first.

**Solution families:** reserve an empty return place; release a holder before
acquiring the next one; use separate routes with more floor space. Later, a
visible mechanical interlock can coordinate the shared bay. These alternatives
trade capacity, layout and control complexity rather than merely changing speed.

**Appeal and diagnosis:** inferred: the player can distinguish a slow upstream
tool from a system in which no action can become possible. Show each retained
piece and what is waiting for what. An inspector should report actual unmet
conditions, not guess a global diagnosis from a stopped animation.

**Recovery and automation:** correct the arrangement while stopped, preserve all
work, then resume. A momentary hand release may demonstrate the cause but is not
an automated solution. Repeat under a downstream blockage and release; a longer
empty belt must not count as solving a cycle if it only delays the next jam.

**Teaching / 3D fit:** require a successful independent lane before introducing
coupling. Use reachable staging shelves and fixed tool faces, not a logic gate
exercise detached from machinery. Expressive interlocks belong later under DESIGN.

**Engineering risk / falsifier:** holder reservation and transfer are proposed
contracts requiring design work; the present opening does not implement them.
Saving midway must retain the real wait/ownership state. Reject if the task is
solved only by a lucky phase, requires recurring manual release, or cannot expose
the causal cycle without an omniscient debugging panel.

**Source and relation:** S2 motivates concurrency/synchronization as vocabulary;
all bay and waiting rules are our inference. This refines
[Opus Magnum's shared region](opus-magnum.md#pattern-opus-magnum-02-trade-separation-for-coordination):
safe non-overlap and eventual progress are separate questions. It differs from
[Factory Town's service drain](factory-town.md#pattern-ft-03-design-a-service-drain-before-rebuilding-the-cell),
which concerns emptying machinery for a rebuild. **Disposition: deferred until
material handoff semantics exist; no new implementation dependency.**

## Pattern spacechem-03: keep both useful results of a separation

**Goal and setup:** candidate here: a new stationary cutting/forming process
separates a composite blank into two different useful intermediate types. Two
downstream products require those different results. Neither output is waste;
finishing one commission must not erase or strand the other result.

**Player verbs and constraints:** orient the complete tool, route each output,
provide finite waiting places, run, stop and inspect retained work. The puzzle
must declare its input-to-output ledger before any prototype: this is not a
license to multiply material or silently introduce a new mass simulation.
The two products must have distinct processing needs, not arbitrary coloured bins.

**Solution families:** dedicated simultaneous routes; an indexed holder that
presents the results sequentially to a shared station; separate finishing cells
with a larger footprint. A large buffer buys tolerance but cannot repair a
permanent mismatch in demand or a blocked mandatory output.

**Appeal:** inferred: a new process changes how the player arranges the factory
and can improve earlier supply while enabling a new product, matching DESIGN's
new-process/new-product direction.

**Failure, recovery and automation:** explain which output prevents the next
operation. Retain both partial inventories through an ordinary stop/reopen;
collecting one must not advance the other twice. Provide an eventual automated
delivery/use route. A bin that needs to be manually emptied forever fails our
automation goal, even if a finite demonstration meets its quota.

**Teaching / 3D fit:** first show the separation with accessible collection on
both sides. Later use directional exits and reachable shelves. Heights and
tool faces should create alternatives only after their physical rules are agreed;
do not add a fictional gravity or clearance rule to manufacture difficulty.

**Engineering risk / falsifier:** authoritative material identities, two-output
admission and atomic partial-work persistence are new unresolved work here.
Reject the card if one output has no useful role, optional deletion solves it,
all routes converge on the same layout, or compulsory upkeep replaces design.

**Source and relation:** S2's simplified bonding model and S3's transformation
vocabulary motivate examining reconfiguration; they do not establish this
specific SpaceChem operation, ratio or failure behavior. This is a refinement
and cross-game synthesis of
[Factorio's blocked coproduct](factorio.md#pattern-factorio-04-a-blocked-coproduct-is-a-process-problem),
which already proposes two useful mechanical fractions, finite destinations,
blocked-output recovery and atomic custody through load. It is not a new
separation/output-custody decision. Compare also the existing
[two-feed proportioning card](factory-town.md#pattern-ft-02-meter-two-feeds-without-hiding-the-missing-ingredient):
input matching alone does not address mandatory *co-output* retention.
**Disposition: candidate for later process design, not selected chemistry.**

## Pattern spacechem-04: transfer a solution when the example layout changes

**Goal and setup:** teaching variant, not another orientation mechanic: after
one clear production success, give the same tools and material objective in a
different approachable arrangement. Remove a misleading example convention
without changing the rule. Ask for an explanation and a working alternative,
not exact placement matching against a hidden blueprint.

**Player verbs and constraints:** approach, inspect, reposition and reconnect
complete stations. Keep authoritative reach, tool faces and quantities unchanged.
Do not use an inaccessible target or camera movement as the trick. A changed
arrangement must permit more than one understandable solution.

**Solution families and appeal:** retain the original cell with a different
transport route; exchange the roles of equivalent positions; rearrange stations
around a required work face. Inferred value: finding an invariant demonstrates
understanding more directly than repeating a highlighted click sequence.

**Failure, recovery and automation:** show whether the refusal concerns access,
orientation, occupied material or a missing connection. Keep work through stopped
revision and require ordinary unattended continuation afterward. Do not teach an
exception through a destructive reset or reward repeated manual corrections.

**Teaching / 3D fit:** precede this variant with one visible collector-to-product
success, not a long instruction chain. Accessible left/right or upper/lower
arrangements can expose a misconception without adding motion programming.
Exact player comprehension still requires actual user observation.

**Engineering risk / falsifier:** keep walkthrough hints separate from Model
validity and actor proximity; an example camera or coloured proxy must not become
an authority rule. Reject if the second arrangement changes the supposed
invariant, only a memorized coordinate works, or success needs more explanatory
text than the original confusion.

**Source and relation:** S3's tutorial diagnosis motivates this variant;
[Factorio's changed-arrangement teaching card](factorio.md#pattern-factorio-07-teach-a-causal-concept-then-change-the-arrangement)
already proposes transfer of the same causal concept to a different site.
[Opus Magnum orientation](opus-magnum.md#pattern-opus-magnum-01-solve-an-orientation-problem-through-layout)
owns the mechanical orientation question. This card refines those ideas with
S3's counterexample/transfer test, not a new teaching or spatial feature. **Disposition:
candidate teaching criterion; no assertion that the present user needs it.**

## Synthesis and next useful work

The remaining new question is the intermediate interface (`spacechem-01`).
Mandatory co-output retention (`spacechem-03`) refines the existing Factorio
card; it is not a second new question. Both need an actual new process and
meaningful product purpose before implementation; neither outranks the current
opening's stock-removal guidance or direct user play.

The waiting-cycle card is a later refinement of the existing shared-workspace
idea. The counterexample card is a teaching test. Generic orientation, startup
versus steady flow, optional score optimization and fault diagnosis already
have cards in the published studies; they are cross-links, not extra discoveries.
In particular, use the existing
[working completion before optional refinement](opus-magnum.md#pattern-opus-magnum-03-working-completion-before-optional-refinement)
instead of turning SpaceChem's metrics into another campaign requirement.

No chemical abstraction, universal scheduler, electrical control system,
precision target, mandatory optimization score or real-time defense layer is
adopted. Technical experiments would need the one existing Model/Session/Store,
explicit custody and stationary geometry contracts, and qualified
[framework behavior](../../engineering/godot-constraints.md). Source inspiration
does not justify embedding engine behavior in game requirements.

## Coverage and review ledger

- **Covered:** bounded primary-source accounts of local/network composition,
  concurrent programming vocabulary, tutorial risks and design intent; four
  explicitly qualified cards: one new interface question and three refinements,
  rather than four claimed independent mechanics discoveries.
- **Remaining:** a verified instruction reference and representative ordinary,
  advanced, blocked and recovered solutions; exact input/output and sync behavior,
  collision/geometry rules, pipeline capacity and restart behavior; current
  executable/version, DLC/ResearchNet/defense coverage and actual player experience.
- **Review:** Platform independently accepted the corrected source/adaptation
  study for partial publication on 2026-10-20. The accepted source is `aac5646`;
  the exact verdict and retained evidence are indexed in `factory-yau.8.5`.
  Platform finding SC-R1 corrected the initial co-output novelty claim by linking
  `factorio-04`; the original frozen draft and finding remain retained. This is
  not an educational efficacy, popularity or observed enjoyment claim.
- **Validation and publication:** owner source/staged/ordinary-hook results and
  immutable handoff are recorded externally and in Beads. Root owns catalogue
  integration and serialized publication; publication does not expand this study's
  source coverage or establish current-build behavior.
- **Closure:** `factory-yau.8.5` stays in progress as a partial study; continuing
  parent `factory-yau.8` stays open. Next distinct coverage is representative
  instruction/production failure evidence, not another marketing summary.
