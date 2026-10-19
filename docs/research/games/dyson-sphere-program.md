# Dyson Sphere Program: capacity, local service and reliable repetition

Status: reviewed and catalogued dated primary-source survey, bounded below;
not a current-build play study. Study Bead: `factory-yau.8.8`.
Owner: factory-platform-review.
Checked: 2026-10-15 UTC. All six pattern cards are original candidates; none
changes [DESIGN](../../../DESIGN.md) or selects an implementation experiment.

## Evidence and source map

This study covers documented stationary production handling, construction supply,
flow diagnosis, blueprint repetition, resource-rate change and logistics-priority
design. It uses vanilla developer announcements from 2021–2026 and a developer
technical article. No game was installed or played, no modpack was evaluated,
and no exact executable, measured rate or player response is established.

The official Steam announcement feed was checked through 2026-10-15. The newest
entry seen was titled V0.10.35.29151; that identifies the announcement snapshot,
not an independently checked shipping executable. Historical rules and announced
changes below retain their dates. In particular, a preview is evidence of the
developer's proposal, not proof of its eventual implementation.

Several Steam article pages exposed only a shell to the text reader. Their full
official bodies were read using Valve's [app-news API](https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=1366540&count=100&maxlength=0&feeds=steam_community_announcements),
including its [earlier-page query](https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=1366540&count=100&maxlength=0&feeds=steam_community_announcements&enddate=1642769762).
Each article link below was resolved from that feed's official external-post
URL. Article titles and dates identify the evidence if the rolling feed moves.
The owner's retained source map records the feed entries, resolved URLs and
cached-body hashes; the public note does not require private tracker access.

| ID and primary source | Date / version | Supported observation and boundary |
| --- | --- | --- |
| S1: [Official game description](https://store.steampowered.com/app/1366540/Dyson_Sphere_Program/) | Checked 2026-10-15; Early Access overview | Icarus builds production chains with conveyors and grid-based construction; blueprints reuse designs as the factory expands. Marketing overview, not evidence for exact rules or balance. |
| S2: [Patch Notes V0.10.29.28154](https://steamcommunity.com/games/1366540/announcements/detail/4034730703034688290) | 2024-02-01; title as published | Adds a sorter handling stacked cargo and changes automatic facility caches according to recipe, duration and speed. Retains existing Mk.III cargo-stacking upgrade values while removing further upgrades. No present-day sorter-rate table inferred. |
| S3: [The Icarus' Evolution release](https://steamcommunity.com/games/1366540/announcements/detail/3144076654124101386) | 2022-01-20 | Introduces an automatic piler combining consecutive cargo, station stack settings and an advanced miner with adjustable speed and freer placement. Historical release behavior, not current throughput measurements. |
| S4: [Patch Notes 0.8.23.9808](https://steamcommunity.com/games/1366540/announcements/detail/3151952246094822839) | 2021-11-18 | Adds belt traffic monitoring and configurable alerts. Reduces automatic material buffers explicitly to shorten production-line warm-up. The old buffer multipliers are not adopted here. |
| S5: [Statistics Panel, Blueprint UI and Game Goals preview](https://steamcommunity.com/games/1366540/announcements/detail/4487367832217059600) | 2024-11-08; preview | Proposes import/export and stored-quantity information, more precise blueprint error displays and adjustable guidance. Does not establish these features' shipping date or current behavior. |
| S6: [Interstellar Logistics Optimization devlog](https://steamcommunity.com/games/1366540/announcements/detail/4157463936690492060) | 2024-05-27; historical system plus upcoming redesign | Explains fair traversal that could choose distant routes, proposed priority layers, and why temporary transport failures need different handling from unavailable routes. Describes reservations and timing complexity; not a complete current routing specification. |
| S7: [Patch Notes 0.9.27.14546](https://steamcommunity.com/games/1366540/announcements/detail/3288214038337615949) | 2022-09-27 | Introduces storage-to-Icarus and storage-to-storage distribution using logistics distributors and bots. Does not establish current coverage, delivery latency or multiplayer behavior. |
| S8: [Patch Notes 0.8.19.7662](https://steamcommunity.com/games/1366540/announcements/detail/3008952177453034897) | 2021-07-23; initial blueprint release | Documents copying a region, repeated pasting, recipes/settings, building statistics and export. Initial-release behavior; no assumption that copying confers materials or current placement permission. |
| S9: [Patch Notes V0.10.34.28455](https://steamcommunity.com/games/1366540/announcements/detail/498345684383040146) | 2026-02-06 | Changes the Fractionator collider to ease Icarus passage through dense layouts. Establishes an access concern, not a complete character-collision or construction-reach model. |
| S10: [Patch Notes 0.7.18.6914–6931](https://steamcommunity.com/games/1366540/announcements/detail/3044975900132654799) | 2021-05-28 | Introduces declining oil extraction with a positive minimum, affected by resource settings and utilization upgrades. A historical resource model, not evidence for current depletion curves. |
| S11: [Youthcat Games' multithreading article](https://gpuopen.com/learn/dyson-sphere-program-new-multithreading/) | 2026-02-12; developer guest article | Explains dependency phases, uneven workloads and synchronization overhead, then profiling and scheduling changes. Its hardware and large-save results do not predict this project's Godot performance. |
| S12: [Patch Notes V0.10.35.29151](https://steamcommunity.com/games/1366540/announcements/detail/693149194510139852) | 2026-10-15; bundled announcement, 0.10.35.29104 subsection | The older subsection records fixes to transfer counts and facility buffers during replacement/dismantling. These are not presented as newly shipped in 29151 or proof of an equivalent defect here. |

## How the engineering challenges develop

**Documented outline:** the overview progresses from small production lines to
a wider industrial network. Later handling tools change the transfer method,
not only processor count: piling, upgraded sorters and distribution provide
different ways to move goods. Blueprints reduce the effort of repeating a
working layout. This is a source-level outline, not a verified unlock sequence.
[S1](https://store.steampowered.com/app/1366540/Dyson_Sphere_Program/),
[S2](https://steamcommunity.com/games/1366540/announcements/detail/4034730703034688290),
[S3](https://steamcommunity.com/games/1366540/announcements/detail/3144076654124101386),
[S7](https://steamcommunity.com/games/1366540/announcements/detail/3288214038337615949),
[S8](https://steamcommunity.com/games/1366540/announcements/detail/3008952177453034897).

**Design inference:** a larger production chain can add planning without adding
a new engineering decision. The useful questions are more specific: is transfer
or processing limiting output; is stock still filling buffers; can the player
service a compact design; and what should happen when a preferred destination
cannot receive goods? These questions offer visible causes and alternative
solutions. Their appeal has not been established by player observation here.

**Failure and recovery evidence:** the monitoring and cache changes distinguish
flow from stored stock and startup from continued operation. The priority devlog
shows that a seemingly helpful fallback can undermine the player's intended
allocation. Newer transfer-count fixes reinforce the need to preserve ownership
when editing a running industrial system.
[S4](https://steamcommunity.com/games/1366540/announcements/detail/3151952246094822839),
[S6](https://steamcommunity.com/games/1366540/announcements/detail/4157463936690492060),
[S12](https://steamcommunity.com/games/1366540/announcements/detail/693149194510139852).

**Fit here:** retain the decisions, then translate them into physical mechanical
arrangements. Electricity, planetary expansion, combat, flying service bots and
the source game's precise recipes are not proposed for the opening. Our actual
parts, nearby character, retained work and gradual automation remain constraints.
The cards' setups and quantities are invented experiment fixtures, not DSP rules.

## Pattern dsp-01: Change the transfer method before duplicating the line

**Goal and verbs:** feed a stationary processor through a narrow passage. The
starter route carries one blank per carrier. A later paired cradle can carry
two, but needs a taller loading envelope and a way to present the blanks at the
destination. Place and orient loaders, route carriers, gear the feed and stop
the drive for edits. The source inspiration is stacked-cargo handling, not a
copied machine or recipe. [S2](https://steamcommunity.com/games/1366540/announcements/detail/4034730703034688290),
[S3](https://steamcommunity.com/games/1366540/announcements/detail/3144076654124101386).

**Constraints and appeal:** passage width and work clearance are hard constraints;
less floor space and lower initial delay are soft rewards. The proposed pleasure
is making a different mechanism solve the same handling problem. Simply turning
a speed slider is not the intended new capability.

**Solution families:** retain two ordinary feeds and take a longer route around
the passage, or load paired cradles and spend height plus loading machinery.
Parallel feeds remain useful and simpler. Pairing reduces route demand but can
delay a lone blank and move the bottleneck to unloading. A larger buffer alone
cannot improve the sustained capacity of the narrow transfer.

**Failure and recovery:** a half-filled cradle retains its actual blank; a full
outlet stops transfer. Clearing the destination resumes the same work. An
automatic partial-load rule would need explicit semantics to avoid recurrent
manual emptying. Unlimited stack height or an invisible second item would erase
the geometric decision. No periodic wear or player refill is introduced.

**Teaching and progression:** establish a single feed first, then show a visible
transfer bottleneck while the processor has spare capacity. Introduce the new
carrier with a short visual explanation. Later variants combine vertical access
and several products; a new handler alone is not an entire progression chapter.

**Adaptation and risks:** fixed subfactory, mechanical gearing and internal
motion only. Carrier contents need authoritative ownership through load, move,
unload, blockage and save/reopen. The carrier's collision envelope cannot be
just a decorative mesh. Representation and acceptable simulation cost remain
unmeasured; this is not a request for free rigid bodies for every blank.

**Falsifier / smallest experiment:** compare an ordinary parallel route and a
paired route in one small stationary fixture with the same input and processor.
Reject the puzzle if the paired method dominates every cost, if unloading cannot
be explained visually, or if pairing creates unavoidable manual draining.
**Disposition:** candidate for later handling research; opening unchanged.

## Pattern dsp-02: Separate startup stock from useful flow

**Goal and verbs:** start two stationary workstations from a limited initial
stock, then keep both supplied by a modest continuous input. Place shallow feed
trays, split the route and change the physical feed order. Stop and retrieve
retained stock when rebuilding. This develops the documented warm-up problem;
the particular two-workstation setup is original.
[S4](https://steamcommunity.com/games/1366540/announcements/detail/3151952246094822839).

**Constraints and appeal:** each workstation needs its recipe's actual work,
but its reserve tray is optional capacity. Filling a large reserve must not be
a hidden precondition to processing. Total stock is finite; startup delay and
space are soft costs. Inference: recognizing that material is waiting in the
wrong place can be more satisfying than adding a nominally faster machine.

**Solution families:** feed branches alternately with a passive distributor,
provide small local trays to both, or use separate longer feeds. A large shared
reserve absorbs interruptions but ties up more material. Capacity and resilience
trade against initial availability; there should be no universal optimal tray.
Expressive sensor programming is unnecessary for the introductory arrangement.

**Failure, diagnosis and recovery:** expose actual passing items, stored blanks,
held work and a blocked output as different facts. A reserve-filling branch may
starve another despite adequate long-term input. Recovery reroutes or retrieves
those same blanks; it does not reset the machines for a refund. Larger buffers
are a degenerate answer if they hide indefinite overproduction or grow without
limit. A solved distribution must restart unattended after ordinary backpressure.

**Teaching and progression:** demonstrate one visibly full tray beside an idle
workstation before introducing aggregate rate displays. The preview's proposed
stock/flow interface is a useful communication idea, not confirmed current DSP
UI behavior. [S5](https://steamcommunity.com/games/1366540/announcements/detail/4487367832217059600).

**Adaptation and risks:** gravity trays on two heights can make the branch order
visible while preserving a usable aisle. These are proposed mechanical parts,
not accepted content. Stock ownership must remain explicit across a transfer;
diagnostic counters must distinguish warm-up, blocked and steady intervals.
Save/reopen must preserve partly filled trays without granting new material.

**Falsifier / smallest experiment:** offer two layouts with the same recurring
input, then stop and restart each with one downstream outlet blocked. Reject if
the only solution is a hidden fill threshold, arbitrary waiting, or an extra
buffer with no meaningful tradeoff. Related: [shapez2-04](shapez-2.md#pattern-shapez2-04-find-the-bottleneck-before-adding-another-machine)
covers general bottleneck tracing; this card adds allocation of startup stock.
**Disposition:** candidate for stationary follow-up, after the basic loop.

## Pattern dsp-03: Supply the worksite without erasing item location

**Goal and verbs:** extend a stationary factory with parts currently stored at
a nearby depot. Route a physical delivery to a work tray, retrieve the parts
and approach the construction position. Move the tray or rearrange the route
as the worksite changes. DSP's storage distribution is evidence for automating
an errand, not a proposal to import its bots or coverage rules.
[S7](https://steamcommunity.com/games/1366540/announcements/detail/3288214038337615949).

**Constraints and appeal:** source parts are real, carriers have capacity and
construction still checks the character's current reach. Receiving a part does
not grant remote build permission. Travel time and delivery footprint reward
planning. The inferred payoff is seeing a factory service its own expansion
without making every store globally accessible.

**Solution families:** carry a small planned kit, build a longer fixed delivery
line, or reserve space for a local staging tray served from above. Carrying is
cheap for one change; a line is more work initially but serves repeated projects.
There must be a useful middle ground before any broader supply capability.

**Failure and recovery:** show source empty, route blocked and destination full
separately. A blocked delivery retains the same parts at a named owner. Cancelled
construction does not summon a second delivery or silently return stock through
the network. An undersupplied plan can remain unfinished while the rest runs.
Once supplied, delivery should continue without repeated player confirmation.

**Teaching and progression:** begin with carried parts, then let repeated real
trips motivate an optional local service route. Do not manufacture a compulsory
forgotten-item chore. Broader delivery or increased construction reach would be
separate later capabilities with their own design decisions.

**Adaptation and risks:** stationary mechanical lift, chute or carrier proposals
must retain physical handoffs and body access. Multiplayer ownership changes
from depot to delivery to tray to pocket need atomic acceptance and persistence;
a saved request cannot duplicate a part after retry. A service controller would
need bounded work and visible cancellation, not a global scan every frame.

**Falsifier / smallest experiment:** compare one rebuild and several extensions
using carried kits versus a local route. Reject if the route merely replaces
walking with equal waiting, needs recurring manual tending, or makes character
position irrelevant. **Disposition:** candidate, later construction-supply scope;
no remote-stock change to the current opening.

## Pattern dsp-04: Reserve for a priority without trapping the supply

**Goal and verbs:** feed two stationary product lines from one distributor. The
first has priority, but may be briefly blocked or deliberately disconnected.
Choose a visible reserve, route the overflow and define what a stopped branch
means. The developer's logistics redesign motivates the distinction between
temporary inability to receive and a route that should no longer reserve stock.
[S6](https://steamcommunity.com/games/1366540/announcements/detail/4157463936690492060).

**Constraints and appeal:** each blank has one owner and limited destinations;
the preferred branch cannot be both promised an item and lose it invisibly.
Throughput, response time and fairness are competing rewards. Inference: an
explainable policy can make a small junction an engineering problem without
requiring an interstellar network.

**Solution families:** dedicate separate feeds; retain a bounded priority reserve
and send surplus onward; or use later explicit control to release a reservation
when a branch is intentionally isolated. Dedicated feeds use more space but are
easy to reason about. A shared route uses less transport but needs clearer state.
Strict priority can starve the second line; unconditional fallback can defeat
the first. These are tradeoffs to demonstrate, not automatic correctness labels.

**Failure and recovery:** blockage must show what is held and why. A broken or
removed route cannot leave an unreachable permanent reservation. Conversely, a
brief full outlet should not cause every waiting item to be stolen by a lower
priority. Recovery changes routing or reserve policy, retaining actual stock.
Repeated manual unblocking would fail the unattended-automation requirement.

**Teaching and progression:** begin with a passive fixed overflow and visible
reserve. General conditions, sensing and policy changes belong with later
expressive controls. Neither priority programming nor a timed delivery quota is
an added requirement for the first playable loop.

**Adaptation and risks:** mechanical gates, finite trays and clutches could
express the policy at one fixed junction. Their exact behavior is unselected.
Admission, reservations and fulfillment need separate authority events; removal,
disconnect and save/reopen need to release or retain the correct claim. The
developer's pair-network cost is not a performance budget for this project.

**Falsifier / smallest experiment:** use two outlets with a declared brief block,
then an intentional disconnect. Compare dedicated feeds with one reserved
junction. Reject if outcomes depend on invisible update order, if reservations
can strand stock indefinitely, or if one setting wins every condition.
**Disposition:** deferred candidate for later controls; not opening scope.

## Pattern dsp-05: Repeat a working cell with its access needs intact

**Goal and verbs:** reproduce a small stationary cell in a second bay, preserving
its feed, drive, working envelope and character access. Select a plan, rotate
it, inspect mismatches and build it from actual parts near the character. DSP
documents reusable plans; the collider adjustment shows that a compact layout
can also affect bodily access.
[S8](https://steamcommunity.com/games/1366540/announcements/detail/3008952177453034897),
[S9](https://steamcommunity.com/games/1366540/announcements/detail/498345684383040146).

**Constraints and appeal:** physical components and usable connections are hard
requirements. Clear access to a service face is a proposed fixture constraint,
not an accepted universal clearance rule. Floor area and shorter supply paths
are soft rewards. The inferred attraction is making a useful module that fits
more than one real space, rather than pasting an opaque answer.

**Solution families:** retain a wide accessible cell, rotate its ports and route
around it, or raise a feed above the aisle while keeping the tool's working
volume clear. The raised version spends height and supports; the wide version
is easier to understand. A service task should not require repeated teardown
once the cell is automated.

**Failure and recovery:** distinguish missing parts, occupied space, a mismatched
port and out-of-reach placement. A plan is descriptive; it neither creates parts
nor changes already-issued request outcomes. Partial construction must preserve
what was actually accepted. The proposed error-focused blueprint display is
communication inspiration from a preview, not confirmed DSP behavior.
[S5](https://steamcommunity.com/games/1366540/announcements/detail/4487367832217059600).

**Teaching and progression:** build and understand one cell before saving a plan.
Show its input, output and drive in a small visual explanation. Repetition then
reduces clerical effort; a later new process should still create a fresh problem.
Pasting many identical cells alone has limited design reward under DESIGN.

**Adaptation and risks:** fixed cells, internal motion and meaningful 3D access;
no mobile-factory dependency. A preview's mesh or picker cannot grant placement
permission. Authority needs per-operation admission, bounded plan size and clear
partial success; saves need stable identities and reproducible plan versions.
The current actor-occupied prototype policy is not a final machinery rule.

**Falsifier / smallest experiment:** compare one wide bay and one bay with a
raised feed. Have a physical character build, reach the work face and recover a
retained item in both. Reject if height adds only decoration or plan automation
hides the operating rule. Related: [shapez2-03](shapez-2.md#pattern-shapez2-03-cross-two-routes-while-keeping-the-worksite-usable)
covers crossing routes; this card adds repetition and construction access.
**Disposition:** candidate layout study; blueprint implementation unselected.

## Pattern dsp-06: Adapt supply without an exhaustion-triggered unlock

**Goal and verbs:** keep an earlier product available while a newly unlocked
process creates additional demand. Continue a simple finite-node route, scale
it where convenient, or construct a more demanding lasting-supply route. Choose
an arrangement and connect its real output; do not wait for depletion to unlock
the alternative. This is a DESIGN-led adaptation, prompted by the source game's
historical example of extraction rates changing over time.
[S10](https://steamcommunity.com/games/1366540/announcements/detail/3044975900132654799).

**Constraints and appeal:** the early source really depletes in our design;
the later method requires a progression milestone and new engineering. Its
particular process and recipe remain open. Space, input logistics and construction
effort can make the old method useful even after the new one is available.
Inference: the interesting choice is rebuilding the means of supply, not waiting
for a countdown to permit progression.

**Solution families:** establish another accessible finite source with automatic
extraction, or build a lasting in-base route with a harder process and logistics.
An exploration shortcut may compete with more elaborate base construction. These
families come from DESIGN, not verified DSP recipe alternatives. None implies
that every source or ingredient must have the same acquisition model.

**Failure and recovery:** a depleted source leaves explicit remaining inventory;
it does not destroy held work downstream. Show source-empty separately from
transfer blockage. A lasting route must ultimately run without repeated visits.
Repeated source replacement with no autonomous alternative, mandatory long
searches and passive regeneration chores would miss the intended reward.

**Teaching and progression:** first learn a complete extraction/process/product
loop. Introduce the alternative through a new process milestone while ordinary
stock can still remain. Active recovery cycles belong later and need more than
accepting a lower average rate. No balance timing is proposed by this source
survey, and no new opening goal is required.

**Adaptation and risks:** stationary mechanical and later fluid/gas candidates
are possible, but the physical process must be chosen before an experiment.
Finite reservoirs, remaining work and changed routes need explicit authoritative
owners and continuation. Neither DSP's historical positive oil floor nor its
utilization upgrades are rules for our resources.

**Falsifier / smallest experiment:** after a process is selected, compare the two
supply routes with both a nearly fresh and a nearly exhausted initial node.
Reject if either case requires waiting for an unlock, compulsory exploration,
or ongoing player replenishment. **Disposition:** resource principle retained
from DESIGN; particular puzzle deferred. Declining-output upkeep is not selected.

## Portability and performance boundaries

The technical article describes a phased simulation with dependency boundaries,
uneven jobs and synchronization costs. The useful inference is to identify actual
independence before parallelizing and measure representative work. It does not
show that this project's current authority, physical characters or item handling
can support DSP's scale. [S11](https://gpuopen.com/learn/dyson-sphere-program-new-multithreading/).

For any selected experiment, distinguish the game rule from its representation:
carrier contents and reservations belong to authoritative state; a belt mesh,
native body, view effect or cached rate display is an adapter. Godot's body/query
behavior needs its own evidence. The study supplies no rollback design, engine
benchmark, multiplayer performance result or production-stack adoption evidence.
No new service, package or engine feature is needed to retain these candidates.

## Synthesis and proposed follow-ups

The strongest fit for a later stationary slice is `dsp-01`: change the method of
handling the same product under a visible geometric limit. `dsp-02` supplies a
distinct diagnostic question about material committed during startup. `dsp-03`
addresses the user's construction-supply friction while retaining item location
and bodily reach. `dsp-05` can inform layout and visual explanation before any
blueprint system is built. All remain proposals after the physical opening.

`dsp-04` belongs with later controls. `dsp-06` records a useful contrast against
importing a decaying-output chore; the actual lasting-supply process is still a
design gap. Electricity, planets, combat, global invisible stock and mandatory
priority configuration have no opening role here. The ordinary loop and user
feedback remain ahead of these research ideas.

A useful next research scope would compare transfer by item, batch and carrier
using an attributed developer demonstration or permitted bounded play record,
covering an actual blocked output, partial batch and edit/reopen. It would test
which rates and failure semantics survive the historical notes. That is a
distinct follow-up, not work claimed as completed by this source survey and not
permission to buy or install the game.

## Coverage and review ledger

- **Covered at source-survey level:** ordinary chain outline; transfer-method
  and cache changes; flow monitoring; local distribution; repeated layouts and
  access; priority/fallback rationale; historical changing resource output;
  dependency/performance cautions. Six varied original cards include explicit
  recovery, automation, geometry, tradeoffs and falsifiers.
- **Excluded or unresolved:** hands-on current-build challenge coverage, exact
  recipes/rates/stack and sorter distances, unlock order, current logistics
  algorithms and delivery coverage, present depletion curves, shipping status
  of the 2024 UI preview, player enjoyment and comparative play evidence.
  Sphere construction, combat, mods and future vehicle plans were not studied.
- **Independent review:** Ops checked the official announcement bodies, dates
  and resolved article links, source qualifications, all six cards and related
  DESIGN requirements. Two wording findings narrowed S2 to saved Mk.III stacking
  values and S12 to the older 29104 subsection of the bundled announcement;
  both were corrected before the final freeze. Source/coverage review found no
  other blocker. This does not endorse whole-game or actual-play coverage.
- **Revision and checks:** source freeze `316c36f` passed all three 143-test
  source/index/hook gates. Ops verified exact final-byte agreement on 2026-10-19
  from Git, reviewed bytes and retained gate logs; a zero-byte older handoff was
  preserved, not reconstructed as pre-loss evidence. Root reviewed the full note
  and agreement before [catalogue integration](../README.md). Only review and
  publication metadata changes here; no engine was run for this study.
- **Closure:** the declared dated source-survey scope is complete after normal
  gates and catalogue integration. DSP is not thoroughly played, its excluded
  current-build systems remain unverified, and no candidate mechanics are adopted.
  Broader/new-version evidence needs an explicitly owned distinct follow-up;
  `factory-yau.8.10` provides the owner's next distinct game study. The continuing
  parent `factory-yau.8` remains open.
