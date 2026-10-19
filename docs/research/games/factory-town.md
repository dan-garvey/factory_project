# Factory Town: gravity routes, usable workspaces and serviceable factories

Status: partial dated source survey; independently reviewed for publication.
Study Bead: `factory-yau.8.10`. Owner: factory-platform-review.
Checked: 2026-10-19 UTC. Scope is the original **Factory Town**, Steam app
860890. Factory Town Idle and Factory Town 2 are separate games and excluded.
The four original cards below are candidates, not adopted game requirements.

## Evidence and source map

This study examines dated developer explanations of stationary transport,
elevation, access, mixing, resource location and recovery. No game was purchased,
installed or played. No current executable, numerical rate, collision solver or
player reaction has been verified. The official announcement feed's latest
numbered original-game post seen was **Update 2.5**, dated 2026-09-29; that does
not establish an installed build or convert every older rule into a current one.

The full developer articles were read through the [official Steam news API](https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=860890&count=100&maxlength=0&feeds=steam_community_announcements).
Each article URL below was resolved from its official feed entry. The retained
source map records eight exact article objects, dates, redirects and hashes.
Later original-game updates were distinguished from cross-promotion for the
other two games in the same feed. No community wiki is treated as primary
technical evidence in this study.

| Source | Date / scope | Observation used and limit |
| --- | --- | --- |
| [Developer's game page](https://easmussen.itch.io/factory-town) and [official Steam overview](https://store.steampowered.com/app/860890/Factory_Town/) | Checked 2026-10-19; overview | Describes 3D terrain, gravity chutes, workers and mechanical transport. Establishes the subject, not exact handling rules. Magic and town simulation are not proposed for this project. |
| [Low-tech wooden gadgets](https://steamcommunity.com/games/860890/announcements/detail/2989814414750503379) | 2021-08-22; historical early-access revision | Earlier automation was introduced to reduce worker micromanagement. Wooden belts trade speed for early availability; minecarts could climb where chutes could not. Also documents access problems from elevated storage. Current unlocks and rates remain unverified. |
| [Block Builder update](https://steamcommunity.com/games/860890/announcements/detail/3064107954155212644) | 2021-02-26; historical revision | Describes a bridge for crossing water, distinguishes navigation from support for other structures, and improves junction construction. These are authored game rules, not evidence for a general structural solver. |
| [Logistics update, .163](https://steamcommunity.com/games/860890/announcements/detail/2918851646648770942) | 2020-09-09; historical revision | Introduces configurable ratio merging and combined filter restrictions. Restricts moving stocked storage in ordinary play. Temporary-starvation behavior of a connected merge input is not fully specified. |
| [Resource rebalance](https://steamcommunity.com/games/860890/announcements/detail/3066356583422561709) | 2021-01-26; historical design rationale | Explains why arbitrary resource placement erased transport decisions; location-dependent yields restore a reason to route goods. Distinguishes input starvation from full output in a production overlay. Current resource multipliers are not assumed. |
| [2.0 update](https://steamcommunity.com/games/860890/announcements/detail/3334366421580475111) | 2022-06-22; historical release | Reorganizes selected-object controls and blocked-output feedback; changes fisheries to depend on harvestable nearby fish tiles. Its regeneration and legacy-map additions are not this project's supply rules. |
| [Update 2.3](https://steamcommunity.com/games/860890/announcements/detail/719042355668190093) | 2026-09-21; original-game update | Reports rendering/work reductions and fixes including duplicate refunds and stale sensor references. Performance claims are not a benchmark for our implementation. |
| [Update 2.4](https://steamcommunity.com/games/860890/announcements/detail/702154493559571519) | 2026-09-23; includes 2.4a hotfix | Corrects out-of-view unit-position behavior introduced by an optimization and misplaced worker alerts. A useful representation caution, not a measured comparison. |
| [Update 2.5](https://steamcommunity.com/games/860890/announcements/detail/702154493559572749) | 2026-09-29; latest numbered post seen | Adds supports and suitable end connectors during some construction operations. Convenience can remove repetitive actions without proving that the resulting layout is usable. Exact current edge cases need play evidence. |

## How the engineering challenges develop

**Documented outline:** workers initially help deliver between production and
markets; mechanical routes reduce that workload. The developer explicitly moved
some simple transport earlier because the previous progression delayed useful
automation. This is evidence for that design rationale, not a claim that every
player had the same experience.
[Overview](https://store.steampowered.com/app/860890/Factory_Town/),
[low-tech revision](https://steamcommunity.com/games/860890/announcements/detail/2989814414750503379).

**Inference:** a slow automatic route can be a worthwhile capability before a
large factory exists. An introductory challenge should give the player an
operating machine to observe, then add geometry or handling choices. Requiring
many trips solely to make automation feel valuable would manufacture a chore.

**Documented scaling concerns:** the resource article argues that unrestricted
local resource creation made transport irrelevant. The logistics article adds
decisions about allocation and filtering. Building placement also affects whether
workers can actually use storage. These are different pressures from merely
requiring more intermediate products.
[Resources](https://steamcommunity.com/games/860890/announcements/detail/3066356583422561709),
[logistics](https://steamcommunity.com/games/860890/announcements/detail/2918851646648770942),
[access](https://steamcommunity.com/games/860890/announcements/detail/2989814414750503379).

**Project boundary:** our player is a controlled physical character, with nearby
construction and actual carried parts. A worker assignment or world cursor in
Factory Town does not establish our build authority. Its historical shared
inventory contribution from crates is specifically not inherited. Likewise,
terrain sculpting, renewable sources and expressive controls retain the staged
limits in [DESIGN](../../../DESIGN.md).

## Pattern ft-01: Spend elevation, or build a way to regain it

**Goal and verbs:** feed a stationary processor across a small site whose source
is higher than its outlet. A gravity route descends successfully, but a later
process needs the work at a higher input. Place and orient chutes, arrange the
processor, or build a driven lift with a safe handoff. This is an original fixture
inspired by the documented difference between chutes and uphill transport.
[Low-tech transport](https://steamcommunity.com/games/860890/announcements/detail/2989814414750503379).

**Constraints and appeal:** the proposed gravity route cannot supply a higher
outlet without an additional mechanism. Working volume, actual input height and
space for the character are hard constraints. Shorter travel and fewer driven
parts are soft rewards. The inferred pleasure is recognizing height as something
the route uses, rather than a cosmetic construction layer.

**Solution families:** lower the downstream workstation and retain a simple
descending path, or raise the feed with a driven lift and keep a compact upper
workcell. A longer route around an obstruction may preserve the needed height.
Each choice spends floor area, height or transmission complexity. Unrestricted
terrain reshaping would remove much of this decision and is not assumed.

**Failure and recovery:** a full receiver stops delivery and retains each item at
its current owner. A lift must resume from its held load after interruption;
neither a restart nor an empty return stroke creates material. An invisible
uphill chute or a lift whose return path intersects its load would make the
mechanism arbitrary. A solved arrangement must cycle without manual resetting.

**Teaching and progression:** show one descending route first, then a visible
height mismatch with an accessible alternative. The lift is a later handling
capability, not extra machinery required by the current collector/press opening.
Fixed cycles and gearing can precede general sensor programming.

**Adaptation and risks:** stationary contraption with internal motion only.
Declare discrete handoff ownership and the lift's actual swept volume. Godot
body behavior, visual item travel and authoritative transfer are separate seams;
no per-item free rigid-body simulation or energy model is selected by this card.

**Falsifier / smallest experiment:** give the same input and processor to one
low, wide layout and one raised layout. Reject if the lift dominates every cost,
if lowering the workcell always removes the whole puzzle, or if block/restart
cannot preserve the same load. Related: [dsp-01](dyson-sphere-program.md#pattern-dsp-01-change-the-transfer-method-before-duplicating-the-line)
concerns batching capacity; this card concerns recovering a useful elevation.
**Disposition:** candidate, after the physical opening.

## Pattern ft-02: Meter two feeds without hiding the missing ingredient

**Goal and verbs:** deliver a repeating group of two blanks from one feed and
one from another to a stationary fixture. Build separate feed lanes and choose
a mechanical metering arrangement. The ratio is an invented experiment value,
not a Factory Town recipe. Its historical merge block shows a source example
of configurable input allocation.
[Logistics update](https://steamcommunity.com/games/860890/announcements/detail/2918851646648770942).

**Constraints and appeal:** the target group and finite local holding space are
hard limits. Throughput, compactness and resilience to unequal arrivals compete.
Inferred satisfaction comes from making visible motion explain the mix. This
belongs after ordinary transfer is understood; exact-count processing remains
later progression, not a condition for the first four plates.

**Solution families:** meter separate lanes into dedicated holding positions,
or use a geared fixed-cycle distributor feeding a shared staging area. Dedicated
positions cost space but expose what is missing. Shared staging is compact but
needs a clear rule for an early or extra blank. A larger untyped storage box
alone does not demonstrate correct grouping.

**Failure and recovery:** a missing feed must remain identifiable. An extra item
stalls the declared process or takes a designed bypass; it is not silently erased.
Stop and retrieve the same retained material, or later automate that recovery.
The source article does not fully specify whether an existing but empty input
blocks its ratio merge, so this study makes no current-game claim about that case.

**Teaching and progression:** show an open metering cycle before introducing a
sealed processor. Begin with fixed motion and arrangement. General sensing and
programmable recovery can appear later, without making manual reset the final
form of a solved factory.

**Adaptation and risks:** two-height lanes and an oriented loading face can make
the spatial layout matter. The pending group needs explicit ownership, sequence
and continuation; saving halfway through the cycle must not consume the same
blank twice. The exact-count probe already exists as separate technical evidence;
this card does not relabel that probe as a selected campaign puzzle.

**Falsifier / smallest experiment:** compare both arrangements under steady,
bursty and temporarily missing input. Reject if a hidden update-order rule picks
the answer, one input can be duplicated by restart, or recovery always requires
a player visit. Distinct from [dsp-04](dyson-sphere-program.md#pattern-dsp-04-reserve-for-a-priority-without-trapping-the-supply):
this is proportioned assembly, not priority between competing destinations.
**Disposition:** deferred candidate for later precision handling.

## Pattern ft-03: Design a service drain before rebuilding the cell

**Goal and verbs:** replace one stationary workstation containing real retained
material while keeping an adjacent branch useful. Stop the affected drive,
retrieve or drain its contents, isolate it and rebuild from actual parts. The
historical restriction on moving full storage is a source example of making
material location matter during edits.
[Stocked storage](https://steamcommunity.com/games/860890/announcements/detail/2918851646648770942).

**Constraints and appeal:** held material cannot disappear with a component;
the character must reach retrieval, and the connected drivetrain's stall rules
still apply. Less downtime and less spare space are soft rewards. The inference
is that serviceability can be an engineering property rather than a repair chore.
This extends a layout question; it does not replace the existing dismantling UI.

**Solution families:** reserve a reachable catch tray and short drain path, or
build a bypass and isolate the cell with a clutch. The tray is simple but occupies
space and may require a deliberate retrieval during this one rebuild. The bypass
uses more machinery but can support later automatic rerouting and repeated work.
Stopping the entire small factory remains a valid beginner solution.

**Failure and recovery:** full downstream storage can prevent draining, so the
inspection must identify the owner of each held item. Moving the full store
through the route, destroying it for a duplicate refund, or resetting its buffer
would bypass the problem. A service operation is deliberate reconfiguration;
ordinary production must not require it periodically to stay alive.

**Teaching and progression:** teach stock-safe removal in the basic loop first.
Only later make continued operation elsewhere a soft challenge. Broad drivetrain
stalls and branch isolation come from DESIGN; branch clutches are not claimed
as part of the current simple opening's authority implementation.

**Adaptation and risks:** fixed cells, mechanical isolation and gravity-assisted
draining. Quantity ownership, stop/edit admission, partial completion and save
state need shared contracts. A retained-work view cannot be inferred from a
decorative item mesh, and a stale command cannot remove a replacement identity.
The source's refund fixes are a caution, not evidence of an equivalent bug here.
[2.3 fixes](https://steamcommunity.com/games/860890/announcements/detail/719042355668190093).

**Falsifier / smallest experiment:** block the outlet, stop one cell and attempt
both a safe full-factory drain and a branch-isolated rebuild. Reject if material
is lost, if isolation has no practical benefit at any reasonable scale, or if
the recovery is compulsory maintenance. **Disposition:** candidate later layout
exercise; current removal-teaching work remains owned separately.

## Pattern ft-04: Bring the process to the source, or bring material to power

**Goal and verbs:** supply a new product from a resource away from the existing
stationary worksite. A simple source-side process reduces the volume to transport
but needs its own physical drive and handling. Route the raw material to an
existing power connection, or build a remote stationary processing cell and
transport its product. This is an original setup motivated by the resource
article's case for meaningful locations.
[Resource rationale](https://steamcommunity.com/games/860890/announcements/detail/3066356583422561709).

**Constraints and appeal:** real distance, elevation, mechanical transmission and
construction parts create hard work. Compact central infrastructure and lower
transport demand compete as soft rewards. The source game's affinity multipliers
are not our rules. Inference: a location changes a good design rather than merely
adding travel time to an otherwise identical checklist.

**Solution families:** centralize processing and build a larger raw-material
route, or distribute the first processing stage and spend parts on local power
and service. A third option can be a harder in-base production method when that
capability is deliberately introduced. Its process and recipe remain unselected;
exploration is not mandatory for every ingredient.

**Failure and recovery:** a depleted finite node stops that source while leaving
downstream work intact. Show source-empty separately from an obstructed route.
The later lasting-supply capability must be progression-driven and capable of
unattended operation; no depletion-triggered unlock or passive waiting challenge
is borrowed from the source game's regeneration systems.

**Teaching and progression:** establish one complete local production line first.
Introduce a new process and a new siting decision together, leaving the earlier
method useful. Do not require a remote factory just to demonstrate basic nearby
placement. Increased demand alone is not the whole progression structure.

**Adaptation and risks:** stationary subfactories joined by actual material
transport; no train, airship or moving-factory requirement. Server-owned stock,
transfers and unloaded-region progress must remain independent of the camera.
Exact world partitioning and simulation cost need separate evidence.

**Falsifier / smallest experiment:** compare one source with an easy drive but
awkward output route and one with the reverse arrangement. Reject if source-side
processing always dominates without a real additional cost, or if remote service
becomes a recurring commute. Related: [dsp-06](dyson-sphere-program.md#pattern-dsp-06-adapt-supply-without-an-exhaustion-triggered-unlock)
records the supply principle; this card adds process/power siting.
**Disposition:** deferred until a later concrete process is selected.

## Synthesis, portability and follow-up

The most direct new contribution is `ft-01`: useful height can be spent by one
route and restored by another mechanism. It fits the selected gravity/tool-face/
clearance direction without requiring travelling factories. `ft-02` belongs
later; `ft-03` and `ft-04` need a scale where service or process siting creates a
real tradeoff.

The source's elevated-storage access problem and its distinction between a
walkable bridge and support for machinery strengthen existing access questions.
They are additional evidence for [shapez2-03](shapez-2.md#pattern-shapez2-03-cross-two-routes-while-keeping-the-worksite-usable)
and [dsp-05](dyson-sphere-program.md#pattern-dsp-05-repeat-a-working-cell-with-its-access-needs-intact),
rather than another new puzzle card. Our controlled body's clearance, reachable
handoff and actual construction permission need their own evidence. The source's
bridge restrictions do not select a structural solver or universal support rule.
[Access](https://steamcommunity.com/games/860890/announcements/detail/2989814414750503379),
[bridge](https://steamcommunity.com/games/860890/announcements/detail/3064107954155212644).
Similarly, automatically proposing supports or connectors need not grant stock
or permission. [2.5](https://steamcommunity.com/games/860890/announcements/detail/702154493559572749).

The low-tech revision is a teaching lesson, not an extra puzzle card: give a
small useful automatic method early, then make a better method introduce an
engineering decision. Do not use worker micromanagement, hidden global inventory,
arbitrary regeneration waits or magic as substitutes for mechanical invention.

The 2.3/2.4 optimization sequence also illustrates a representation risk: reducing
work for unseen units needed a later position correction. Our adapter may cull
rendering; authoritative stock, operating machinery and actor authority cannot
be defined by camera visibility. That is a design inference from the posts,
not a measured Godot limitation or evidence that the same defect exists here.
[2.3](https://steamcommunity.com/games/860890/announcements/detail/719042355668190093),
[2.4](https://steamcommunity.com/games/860890/announcements/detail/702154493559571519).

A useful follow-up would inspect a dated developer demonstration of an uphill
handoff and a temporarily starved ratio merge. It should distinguish an absent
input path from a connected empty path, a visual queue from real retained stock,
and ordinary play from creative exceptions. Those behaviors are not established
by this announcement survey. No implementation experiment is selected here.

## Coverage and review ledger

- **Source coverage so far:** developer overview; historical early transport,
  gravity/access and structural distinctions; ratio/filter design; stock-safe
  movement restriction; location rationale; newer construction convenience and
  representation cautions. Four original candidate cards are drafted; access
  comparisons are cross-linked to existing cards rather than counted again.
- **Remaining gaps:** current chute geometry, junction/backpressure rules,
  temporary-starvation behavior, exact rates and unlock sequence, detailed
  current inventory/packed-item semantics, direct play or attributed challenge
  demonstrations, and hands-on evaluation of proposed adaptations. No broad campaign, magic,
  train, boat or other-game coverage is claimed.
- **Independent review and checks:** Ops accepted the exact frozen source/card
  study for partial publication; root reviewed the source evidence, design fit
  and compatibility with the published DSP and shapez 2 notes. The author's
  source, immutable staged and normal-hook gates each passed 143 tooling tests.
  Publication changes only review metadata and the catalogue, not source claims
  or cards. No engine was run; these checks do not establish play or mechanics.
- **Closure and next scope:** `factory-yau.8.10` stays open. A later closure
  requires explicit thorough declared coverage, resolved findings, final gates,
  independent agreement and root [catalogue integration](../README.md). The
  continuing parent `factory-yau.8` remains open. P1 physical-character and
  stationary opening evidence preempts this research at every work boundary.
