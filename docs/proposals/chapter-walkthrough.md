# First-chapter build, diagnose, recover and expand walkthrough

Status: **paper walkthrough**, proposed for `factory-yau.1.3`, 2026-10-14.
No playtest or runtime exists here. This is an actionable storyboard and future
demo acceptance sheet for the provisional softmetal chapter, not approval of
its recipes, parts, unlocks, camera, collision feedback or production stack.
[DESIGN.md](../../DESIGN.md) owns requirements. Placeholder shapes and labels
are sufficient to test the actions below; finished art is unnecessary.

## Fixture and dependencies

Use [first-chapter-challenge.md](first-chapter-challenge.md): blank → plate A;
opposed channel rolls → guide channel B; 12 A + 2 B → kit C. The illustrative
four-plate check and three-kit commission remain paper quantities. Confirming
inventory is distinct from automation evidence and physical off-site delivery;
consumption and individual/team/world credit remain unresolved.

The layout input is `docs/proposals/first-chapter-layouts.md` at commit
`04052feb249e8736f42703266e545b51d2133801` on `design/chapter-layouts`, still
pending independent review when this draft was written. Its R rotary and G
gantry arrangements are conditional, not accepted hardware. This walkthrough
uses G for a concrete build and retains R as an alternative and scaling control.
If that proposal changes, reconcile its phases before implementing this sheet.

The G fixture needs a fixed-stroke carrier, a finite dwell at each endpoint,
supported anvils, a stripper, closed nest floors during travel, and a dock that
unloads before loading. These are proposed mechanisms requiring review. A
continuously moving carrier or instant end-stop reversal does not provide a
pressing interval. Do not hide missing functions in a scripted success event.

Prepare one small raised deck on a designed ledge, without assuming early
excavation. Keep the source stock and construction cache physically local.
Place a raised feed hopper, a lower discharge belt and a press support so the
player must distinguish three occupied levels. A crossing shaft and a second
useful conveyor branch make inspection crowded without blocking every access
route. Supports must stay outside carrier travel and the ram envelope.

```text
side section:     upper feed                 ram lift/drop space
                     |                            v
working deck:    [dock/nest] <--- x stroke ---> [press/anvil]
                     v
lower level:     receiving belt ---> local plate bin

topology:        source --+--> U: useful conveyor / takeaway
                         +--> K: coupling --> M: common cycle shaft
                                              | carrier + press + dock gates
```

K isolates the **whole synchronized M unit**, never just its stuck carrier
while its press continues. U can demonstrate operation elsewhere. The baseline
obstruction run uses a closed clutch; a later recovery run can substitute a
slipping coupling, subject to acceptance of that part's behavior. These are two
explicit configurations, not a clutch silently becoming an automatic slip.

Record initial parts, blanks, products and recoverable in-process contents.
Fixture stock may be reset between trials with that reset disclosed; nothing
in the played route silently refills a hopper, teleports parts or clears a jam.
Finite starting feed only proves local operation while supplies last. Source
lifecycles, construction bootstrap, packing automation and lasting supply are
owned by `factory-yau.2.5` and the chapter decision packet.

## Storyboard

Each beat gives the player an objective, an observable state, an action and a
completion witness. A presenter may seed a fault before a run and record it in
the evidence. During diagnosis, first let the participant inspect; any hint or
presenter intervention is evidence about legibility, not an unassisted success.

### 1. Make A and find the working volumes

The manager's placeholder commission asks for plates, with a related optional
project to remove press tending. It names a product and purpose, not the one
permitted machine. Fetch blanks and parts from their actual local locations.
Build the starter press while its mechanism is in the fixture's agreed parked,
aligned edit state. Which stopped/docked states permit editing remains a later
contract; stopping in an arbitrary operating pose is not assumed sufficient.

Observe one complete cycle from a position clear of machinery. Place and remove
work only through the provisional stationary interaction, with power stopped
as required by that fixture. No animation of a hand inside a running ram is
needed, and no injury rule is inferred. Trace one blank into one retained plate.
The player confirms the requested inventory; that succeeds even if the handling
was manual. A plate disappearing during the check must not be invented to stand
in for an undecided shipping/consumption rule.

Witness: the participant can point out the downward tool face, support below
the work, ram clearance above it, and why a flush solid floor prevents the
proposed downward discharge. Raising the deck or using the ledge is a working
choice; an arbitrary minimum-height recipe tag is not the explanation.

### 2. Build away the tending in a crowded assembly

Offer G and R explanations without requiring the participant to copy either.
For the G example, build and inspect the lower outlet before obscuring it with
the deck; add anvils and press bank, then the carrier/rails, upper hopper and
transmission. This is an offered build order, not an enforced placement rule.
The raised feed, crossing shaft and press bank should remain visible together
from at least one reachable inspection position. Record any need to dismantle
unrelated equipment just to select or understand the buried outlet.

Trace the fixed cycle: dock discharges the old plate, closes its floor, loads
one blank; carrier travels to the press, dwells on the supported anvil while the
head forms and retracts; carrier returns with its plate. Gates and floors finish
closing before travel. An empty feed pass creates no product; a blocked outlet
must not allow loading on top of retained contents. The common shaft supplies
phase, not independent timers that happen to agree at startup.

Witness: after the initial fill, run three complete return-to-dock cycles as a
small fixture sample, without player loading or unloading. Count input removed,
plates collected and contents still in flight; each formed plate corresponds
to one blank. Three cycles are an acceptance sample, not a game rate or proof
of indefinite reliability. If feed, stripping or discharge needs an unseen
manual action, record the missing part and reject this automation witness.

### 3. Diagnose a direction fault

Seed the fault in the new roll branch while stopped: route equal roll shafts
so the two nip surfaces do not both pull toward the outlet. Supply one blank
through its supported inlet. Do not assume every wrong direction is a solid
collision or that it necessarily stalls the entire source; a part may simply
fail to advance. Observe what the implemented rule actually does.

Ask the participant to trace source → meshes → shafts → contacting surfaces.
They should locate the direction mismatch, stop/park the branch and correct the
gear route/orientation in the allowed edit state. An idler is one candidate;
extra gearing is not mandatory if another valid route solves it. Keep feedstock,
head profile and output support unchanged to discriminate the correction.

Witness: the corrected nip pulls the same sort of blank through the channel
profile and produces B. The participant can explain both surface directions,
not merely repeat a gear count. The new profile/process must genuinely enable B;
if the old heads can produce it, accept that construction and revisit the
chapter premise. Channel B creates a reason to learn rolls independent of A's
capacity. Flat tooling for A is a later optional adaptation.

### 4. Trace an obstruction, then isolate and recover manually

In a separate fault run, seed an unintended solid obstruction in M's carrier
travel, distinct from intended press/material contact. With K closed, attempt
one cycle. The accepted behavior is a stall of the mechanically connected
drivetrain without machinery damage: M and connected U stop. Preserve contents,
tool phase and transforms; the jam does not consume a blank or award a plate.
Exact contact feedback and injury consequences remain outside this storyboard.

The participant traces the stopped shaft through the crowded assembly to its
cause, opens K through the permitted control interaction, and observes U resume
while the isolated M remains stationary. This proves an actual topology change;
a highlighted branch with no resulting difference in operation is insufficient.

Stop/secure and park M as required by the future edit contract, remove the
obstruction through an allowed stationary action, inspect retained work and
restore the drive. Do not remove an anvil or feed support to make a collision
vanish. The fixture must specify a realizable restart: either its common drive
retains phase through the stall, or a bounded stationary rehome procedure
accounts for every retained item before a fresh cycle. No teleport to the dock,
independent press restart, deleted contents or whole-world reset counts as
recovery. The appropriate rehome mechanism remains a named implementation gap.

Witness: U operates while M is isolated; after correction M completes the held
work once and resumes feed/discharge, with no duplicated plate or machinery
damage. Record where the stall occurred in the cycle. Repeat at another phase
when a runnable fixture exists; startup-only success cannot validate mid-cycle
restart. If resynchronization is undefined, this beat is blocked, not passed.

### 5. Let a designed path recover from backpressure

Use an occupied lower receiver as a distinct, recoverable fault. First show
that retained output prevents the dock loading another blank. Backpressure is
not permission to destroy output or keep pressing into an occupied nest.
Whether this stop is represented as process inhibition or mechanical blocking
must be declared in the fixture; it is not a new universal collision rule.

For a proposed designed recovery, put the receiving takeaway on U and use a
slipping coupling at K. Temporarily hold the downstream consumer; M stops when
it cannot discharge while U's source remains available. Restore consumer
capacity through a normal operating interaction. U drains the receiver; a
proposed mechanical backpressure stop releases and M continues its retained
phase. This requires a real capacity-dependent interlock and retained common
phase. Neither is established by the paper drawing. It must not auto-repeat a
press stroke or load a second blank when the dock resumes halfway through.

Witness: after downstream capacity returns, no player clears the nest or
restarts each cycle; the retained plate leaves once and new blanks flow. With
the same full receiver and takeaway path disabled, the machine stays blocked.
This control distinguishes physical recovery from a scripted timed reset.
The slipping coupling's load/heat/wear rules remain open; this demo cannot
quietly introduce recurring replacement or a new consumable chore.

This demonstrates a designed recovery from a bounded capacity fault, not an
automatic solution to arbitrary solid obstructions. Opening a clutch and
removing a solid by hand in beat 4 remains manual recovery. If the proposed
passive interlock/slip behavior cannot be realized with acceptable early parts,
revise the chapter or defer that recovery feature explicitly. Do not smuggle
sensors, counters or general programmable controls into the early required path.

### 6. Expand or adapt because C needs more A

Present the kit commission after B: the illustrative three kits require
36 A and 6 B. The participant can retain their press line, widen it, duplicate
small units, or adapt the learned rolls with flat tooling for A. Packing and
off-site shipping remain separate interactions under unresolved contracts;
their placeholder presentation must not be called a solved automation route.

For G, park in the permitted edit state, extend a lane along y, add its hopper,
nest, anvil/head, lower receiver and transverse drive, and keep x travel fixed.
Trace one blank in each lane through dwell and discharge. Check the wider
carrier's support and the hidden lower belt rather than counting heads alone.
Compare the same addition to R: a concentric track increases radius, swept
space, station span and outer travel. Include repeated small R units as a
serious control; G has no guaranteed universal footprint or capacity advantage.

For optional flat-roll A, keep the original press usable and physically route
some of the same feedstock to flat tooling. Compare useful output, handling,
access, footprint, construction effort and actual supported paths. Changing
speed alone or duplicating a head is a control, not evidence of the desired
new-method reward. If rolls confer no worthwhile benefit, record that finding
and revisit the challenge rather than forbid the press recipe.

Witness: an added lane works without lengthening G's motion-axis travel, and
its real feed/return/support costs are visible. The player can choose a viable
old method for C. Confirmed kit inventory establishes an ordinary milestone;
unattended cycles establish only the automation actually observed. A supply
project may be offered by the provisional B milestone while the seam still
contains blanks; exhaustion must not trigger the unlock.

## Inspectable visual explanation

Provide contextual demonstrations for press handling, direction and isolation.
They are read-only scenes with camera rotation and zoom, following the accepted
Ponder-like direction. Use the same mechanism definitions/behavior as the real
fixture where practical; scripted presentation must not bypass a missing dwell,
hide a transfer, or show a different stall topology. Replay/step, arrows, labels,
counts and temporary cutaway views below are presentation candidates to test,
not selected live construction or collision feedback.

| Shot | Show | What the participant should be able to inspect |
| --- | --- | --- |
| Whole assembly | Upper hopper, working deck, ram envelope and lower outlet | Rotate and zoom to follow a blank down through the actual levels; retain spatial context |
| One carrier cycle | Dock unload-before-load, travel, work dwell, return | Which object supports/retains the work at every handoff; why slower continuous motion is insufficient |
| Gear route | A shaft mesh, then both roll contact surfaces | How changing one route changes the nip direction while preserving the product/tooling |
| Failure and isolation | Same obstruction with K closed, then open | Why U stops with M and resumes when M is isolated; M stays blocked |
| Recovery | Retained work and common phase, then full receiver draining | Where the old plate goes and what must clear before a new blank enters |
| Growth comparison | One added G lane, one outer R track and another small R | Fixed stroke versus larger sweep, with additional handling/support visible |

The participant returns to their factory to apply the rule. They cannot place,
remove or regear parts inside these explanations; there is no editable tutorial
sandbox. Rotation/zoom here does not choose the main game's perspective. A
working demonstration is teaching evidence, not proof the crowded live build
can be navigated or understood.

## Runnable demo acceptance and evidence handoff

This sheet proposes a bounded chapter demo, not a full first release or an
instruction to install an engine. Obtain the existing trial/playable decisions
before implementation (`factory-yau.3.2`, `.1.6`, `.2.3`, `.3.5` as applicable).
The implementation owner should attach an exact revision, fixture setup and
part assumptions, command/build route, initial/final contents and recorded
participant observations to each row. Preserve failed runs and interventions.

| Witness | Pass condition for a future runnable demo | Current evidence |
| --- | --- | --- |
| Build and inspect | Participant constructs handling and identifies all three levels without editing in motion; retrieval stays physical | Paper storyboard only |
| Repeat and account | Three completed sample cycles without tending; blanks equal plates plus accounted remaining contents | Not run |
| Diagnose direction | Participant finds and corrects the seeded nip-direction fault; B forms through the corrected route | Not run |
| Stall and isolate | Closed K stops connected U/M without damage; open K restores U while M stays blocked | Not run |
| Manual restart | Corrected M completes retained work once; phase and contents survive, including a mid-cycle fault | Restart contract unresolved; not run |
| Designed recovery | Receiver drains on independent U; interlock/slip permits retained cycle to continue; disabled takeaway control stays blocked | Proposed parts unproven; not run |
| Expand and choose | Additional G lane keeps stroke length; R/duplication controls and optional roll A preserve viable old methods | Conditional geometry only |
| Explain and apply | Rotate/zoom reveals feed, dwell, direction and isolation; participant applies one rule to the live factory | No teaching scene or participant session |
| Chapter milestone | Inventory confirmation and optional automation evidence remain separate; delivery/consumption/credit follow an accepted contract | Content and ownership decisions pending |

For usability, record selection mistakes, lost orientation, obscured outlets,
forced dismantling, retrieval trips, hints used and the participant's explanation
of each fault. Use these observations to compare candidate navigation/inspection
methods; no camera or numerical time-to-solve target is selected here. A
presenter succeeding from memory does not establish a new player's diagnosis.

The future user session should ask whether the crowded build is comfortable,
whether shaft connectivity is legible, whether stopping/editing/restarting is
understandable, whether the two A routes warrant a choice, and whether the
explanation helps without prescribing a blueprint. Failure should yield a
specific construction/teaching follow-up rather than silently settle deferred
warnings, clearance previews, activation restrictions or injury rules.

Independent chapter review remains `factory-yau.1.5`; actual combined chapter
integration and user play are `factory-yau.6.3`–`.6.5`. This local storyboard does
not replace the common prototype witness for headless authority, two clients,
save/resume, passengers and transfers. Multiple teams, later controls, trains,
fluid/gas systems, lasting acquisition and campaign endings remain intended
scope requiring their own staging. No performance or fun claim follows from
tooling checks on this document.

Sources: [play loop](../../DESIGN.md#possible-play-loop--to-validate),
[construction and movement](../../DESIGN.md#construction-and-movement),
[automation and stalls](../../DESIGN.md#complexity-and-automation),
[teaching](../../DESIGN.md#ponder-like-explanations),
[quest completion](../../DESIGN.md#quest-completion),
[review finding 5](../../DESIGN_REVIEW.md#prioritized-findings), and
[roadmap gates](../../ROADMAP.md#convergence-and-decision-gates).
