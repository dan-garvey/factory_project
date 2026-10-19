# Study: Satisfactory — stationary 3D routing and construction

Status: **partial**, source research in progress; not thoroughly studied.
Study Bead: `factory-yau.8.2`. Owner: factory-playability. Checked 2026-10-15 UTC.

Scope so far: selected stationary construction/logistics changes documented in
the 1.0 and 1.1 releases, their 1.2 context, and five original puzzle adaptations.
The second pass adds a documented input-substitution example and the developer's
research-choice rationale; it remains a source study rather than actual play.
The official publisher feed includes maintenance version **1.2.4.1**, posted
2026-10-12. No executable or changelist/build was tested. The older search listing
ending at 1.2.4.0 was insufficient to establish the current release; the dated
publisher feed was checked directly. [S01], [S02], [S03], [S04]

Evidence access: developer-authored Steam announcements, including their public
publisher API text and UTC metadata; cached excerpts of the official collaborative
wiki. Several full wiki page opens returned HTTP 403. Those excerpts are labelled
as such, not represented as a full manual read or current-build validation.
No first-hand play, installation, purchase, watched video/timestamp or popularity
claim is included. A written announcement's embedded trailer was not watched.

This follows the [continuing research contract](../README.md) and
[template](../STUDY_TEMPLATE.md). The physical-character/stationary opening in
[DESIGN](../../../DESIGN.md) takes priority. Factorio has a separate owned study;
the overlapping buffering and interface lessons below identify their relation
instead of claiming another game invented them. Mobile vehicles, trains,
campaign narrative, deep fluid simulation and optimization exploits are outside
this first pass, rather than assumed absent from Satisfactory.

## Evidence and source map

All access dates are 2026-10-15 UTC. Developer announcements are primary evidence
of the documented release changes. Wiki material is collaborative reference
evidence and currently limited to the returned cached text. Analysis and original
adaptations are distinguished from both.

| ID | Source / dated section read | Support and limit |
| --- | --- | --- |
| S01 | [Official 1.0 launch announcement](https://steamstore-a.akamaihd.net/news/externalpost/steam_community_announcements/6242640076615256249), 2024-09-10; blueprint, MAM and Alien Technology sections | Larger blueprint designers, saved Hard Drive choices with one replacement pair, and a researched Dimensional Depot for building/crafting supplies. Historical feature introduction, not proof of all current limits. |
| S02 | [Official 1.1 release announcement](https://steamstore-a.akamaihd.net/news/externalpost/steam_community_announcements/1801617199560021), 2025-06-10; logistics and quality-of-life sections | Lift-mounted splitters/mergers, configurable wall crossings, throughput monitor, blueprint connection preview, vertical nudging and removal of its distance limit. This concerns preview editing; final placement range remains untested. The April experimental announcement is not substituted for shipped June notes. |
| S03 | [Official 1.2 release announcement](https://steamstore-a.akamaihd.net/news/externalpost/steam_community_announcements/1833968530900760), 2026-06-02 | Version boundary and additional pipeline junction vocabulary. Vehicle changes are explicitly not researched/adapted here. |
| S04 | [Official 1.2.4.1 maintenance announcement](https://steamstore-a.akamaihd.net/news/externalpost/steam_community_announcements/1846018067941164), 2026-10-12 | Recent monitor-related crash fixes show why old release notes are not a current-build correctness or performance certificate. No running-build claim. |
| S05 | [Official wiki: Manifold](https://satisfactory.wiki.gg/wiki/Manifold), cached principles excerpt | Serial splitters, buffer filling and sufficient-rate conditions. Full direct page access failed; no exact filling time is claimed. |
| S06 | [Official wiki: Build Gun](https://satisfactory.wiki.gg/wiki/Build_Gun), cached construction/lock/nudge sections | Hologram feedback, finite nominal build range and separate preview editing. The interaction of unlimited nudging and final range admission was not tested and remains unresolved. |
| S07 | [Official wiki: Resource Node](https://satisfactory.wiki.gg/wiki/Resource_Node), cached introduction | The manual describes nodes as non-depleting. This conflicts with our intended early finite-node rule, so it is a comparison rather than an adopted default. |
| S08 | [Official wiki: Hard Drive](https://satisfactory.wiki.gg/wiki/Hard_Drive), cached alternate-recipe section | Alternative processes trade inputs, space and other costs. Exact recipe counts conflict across cached guide/MAM pages; no count, best recipe or complete progression is asserted. |
| S09 | [Official wiki: Head lift](https://satisfactory.wiki.gg/wiki/Head_lift), cached introduction; [Pipeline](https://satisfactory.wiki.gg/wiki/Pipeline), cached fluctuations section | Qualitative height/flow distinction and a version-change caveat. Numeric limits, old exploit advice and complete 1.2 fluid behavior remain unverified; no fluid pattern is claimed thoroughly studied. |
| S10 | [Official 1.0 preview: Only 2 weeks left](https://steamstore-a.akamaihd.net/news/externalpost/steam_community_announcements/5875595438703071739), 2024-08-26; ALT. RECIPES AND HARD DRIVES | Developer rationale for separating pending recipe choices from later research, a once-per-drive replacement choice and progression-filtered options. A preview and design rationale, cross-checked against shipped S01; not a current exhaustive reward-pool model. |
| S11 | [Official wiki: Wire](https://satisfactory.wiki.gg/wiki/Wire), cached Obtaining / Crafting table | Default copper-based Wire and alternate Iron Wire use different ingredients and output rates. Unversioned cached table only; no claim of an installed 1.2 recipe test, universal best choice or complete upstream-cost comparison. |

The dated publisher metadata and relevant announcement text are retained in the
study's external evidence handoff. Individual post links above are the sources,
not search-result pages. The source access limitation is a reason to keep this
study partial, not to fill missing mechanics from memory.

## How the engineering challenges develop

The source-backed distinction worth investigating is between **placing more
machines** and improving how a three-dimensional installation can be constructed,
fed, observed and repeated. The 1.1 vertical attachments and construction changes
provide concrete vocabulary for that investigation. Blueprint and supply tools
can reduce the repeated execution cost after the first working module. [S01], [S02]

This suggests two changes in the problem as a factory develops: recipe options
can change which local supply matters, while research presentation can let a
player investigate options without stopping other work. The dated 1.0 preview
explicitly identifies pending choices blocking further research as an earlier
problem. Shipped 1.0 separates researched drives into a library and permits one
replacement of the offered pair. This supports the presentation distinction;
it does not demonstrate a complete learning curve or current save behavior.
[S01], [S10]

Representative early-to-late production lines, unlock prerequisites, failure
feedback and actual repeatable behavior still need stronger coverage. The Wire
table below is one scoped example, not a survey of alternate recipes. Fluid
recovery remains unresolved. [S08], [S09], [S11]

Two source-game differences matter immediately. Its described non-depleting
nodes must not silently replace our early depletion requirement. Its researched
remote construction supplies must not become our initial carried kit or resolve
our individual/team progression model. Electricity, numerical clock upgrades
and unrestricted access are not proposed imports. [S01], [S07]; DESIGN.

## Pattern satisfactory-01: use height to separate routing from service access

- **Goal and setup:** serve several fixed workstations while retaining a walkable
  service route. Source behavior: the 1.1 notes introduce splitters/mergers on a
  conveyor lift, including intermediate attachment points, and adjustable wall
  crossings. This changes available arrangements, not merely a transport rate.
  [S02]
- **Player verbs:** approach, place, orient, branch and cross transport routes;
  arrange access to the stationary machines and inspect their actual ports.
- **Constraints:** port direction, occupied volume and character access are hard
  constraints in the proposed task. Footprint, parts and readable servicing are
  soft rewards. A tall machine that is only decorative adds no decision.
- **Solution families:** use a low wide route around the service lane; lift a
  shared feed above the lane and branch downward; move the workstations to give
  them separate approaches. Compactness trades against lifting infrastructure
  and construction access.
- **Appeal:** inference: the player invents an arrangement that works in both
  the material network and the space they physically occupy.
- **Failure and recovery:** show the blocked route or wrong interface without
  destroying material. A solved route should feed stations unattended. Invisible
  port connections or clipping all routes through everything would remove the
  spatial problem; forced repeated ladder trips would turn access into upkeep.
- **Teaching and progression:** first establish one working ground-level handoff.
  Add an actual crossing or upper intake later, after the character opening.
  Teach a useful new arrangement rather than requiring a moving factory.
- **Adaptation here:** original candidate: a mechanical chain lift above a
  stationary service corridor versus a longer horizontal feed around it. A later
  top-fed forming tool can make the lifted route useful for a new product.
  No specific lift, recipe, clearance or part cost is selected.
- **Engineering risks:** authoritative port frames and item holders, meaningful
  swept/working clearance and actual character collisions must agree. The current
  opening's planar construction grid is an adapter limit, not a Godot limit or
  proof that the vertical version already exists.
- **Falsifier / smallest experiment:** build both routes with the same finite
  inputs and show a real difference in access, footprint or useful feeding.
  If the elevated route is a cosmetic duplicate, discard that version.
- **Sources / related patterns:** S02; related Factorio `factorio-02/03` cover
  interface/capacity choices, while this candidate focuses on service volume.
- **Disposition:** candidate for later stationary experimentation; not selected
  ahead of physical-character/reach acceptance.

## Pattern satisfactory-02: distinguish a filling network from an undersupplied one

- **Goal and setup:** feed several consumers from a constrained supply. The
  cached manual describes a serial manifold that stabilizes after earlier buffers
  fill, provided source and conveyor capacity meet demand. Those qualifications
  are part of the behavior, not a promise that every chain eventually works.
  [S05]
- **Player verbs:** split or merge feeds, add an injection point, reduce a
  consumer's demand, choose a parallel route and inspect holders over time.
- **Constraints:** conserved supply and finite buffers are hard limits. Startup
  delay, extra transport, compactness and visibility create soft tradeoffs.
  Waiting cannot repair a sustained capacity deficit.
- **Solution families:** balance feeds explicitly for predictable startup; use
  a compact serial feed and tolerate its filling transient; inject supply farther
  along a long line. Each still needs sufficient total and local capacity.
- **Appeal:** inference: understanding one visible transient can replace repeated
  manual adjustments, provided the cause is legible.
- **Failure and recovery:** an empty last consumer can mean initial filling or
  permanent starvation. Diagnose supply and occupancy separately. Giant buffers
  can conceal the latter. Manual top-ups are not an automated solution.
- **Teaching and progression:** original paper example only: three consumers need
  one item per beat each. A source of three can support them once bounded buffers
  settle; a source of two cannot. Compare early and later cuts, rather than
  declaring success from the first full machine. These are not game recipe rates.
- **Adaptation here:** compare a stationary mechanical feed with separate takeoffs
  against a shared sequential distribution path. Prefer geometry and predictable
  cycles before introducing later expressive controls. Any experiment uses an
  explicitly finite stock and declares its observation window; no hidden refill.
- **Engineering risks:** per-holder custody, initial conditions, exact work per
  cycle and backpressure must be recorded. A transport monitor needs a stated
  measurement interval; the developer's monitor description is an example of
  that distinction, not a performance target for our game. [S02]
- **Falsifier / smallest experiment:** stop the input, account for every remaining
  unit, then restart the declared feed. If a supposedly sustained result was
  actually spending initial buffer stock, reject the capacity claim.
- **Sources / related patterns:** S05 and the S02 monitor section; Factorio
  `factorio-03` covers the broader bottleneck-versus-storage distinction.
- **Disposition:** candidate; actual Satisfactory startup timings and edge cases
  remain a deeper study, not measured facts here.

## Pattern satisfactory-03: remove repeated execution after designing the module

- **Goal and setup:** extend a solved fixed installation while avoiding repeated
  placement and supply errands. Source behavior: 1.0 adds larger blueprint tools
  and researched remote building/crafting supplies; 1.1 adds previewed automatic
  connections at module interfaces. These are different conveniences. [S01], [S02]
- **Player verbs:** define a module, inspect its boundary, stage materials,
  repeat construction and explicitly confirm intended connections.
- **Constraints:** correct interfaces and actual material custody are hard.
  Reduced repetitive execution is a soft reward. A plan is not an installed
  machine, and stored stock is not automatically carried construction stock.
- **Solution families:** hand-build locally with a small kit; stage a supplied
  construction area; later repeat modules through a capability that actually
  delivers their parts. Sharing trunks saves parts but couples replacements;
  isolated modules cost space and simplify diagnosis.
- **Appeal:** inference: removing a solved chore leaves attention for new process
  design. Bigger copied arrays alone need not create a new engineering problem.
- **Failure and recovery:** preview the interface being joined, retain stock when
  a neighboring module changes and distinguish queued work from completed work.
  Automatic connection must not silently target a replacement. A global material
  pool may remove errands while also removing logistical meaning.
- **Teaching and progression:** construct and repair one module before granting
  repeated construction. A new supply service should be a distinct capability,
  not an unexplained permission or inventory expansion.
- **Adaptation here:** original later candidate: a mechanically supplied staging
  platform for a stationary upper workshop. It reduces repeated fetching while
  retaining local coverage and actual delivery. Satisfactory's dimensional storage
  is a comparison; it is not our adopted answer to construction supply.
- **Engineering risks:** one parts owner, intended endpoint identities, grouped
  refunds, proximity, concurrent requests and continuation need explicit contracts.
  A saved blueprint must not clone campaign inventory. Our team/learning/credit
  model remains separate and unresolved where DESIGN says so.
- **Falsifier / smallest experiment:** move or replace the intended receiving
  interface while a construction request waits. If it spends stock, retargets
  or reports completion before actual fulfillment, the convenience is misleading.
- **Sources / related patterns:** S01, S02; Factorio `factorio-01/06` address the
  same planning/fulfillment and repeatable-interface family. This card adds the
  specific 3D staging/access question rather than claiming a novel generic pattern.
- **Disposition:** deferred; no blueprint, remote-depot or supply-system feature
  is added to the current opening by this study.

## Pattern satisfactory-04: an alternate input changes the installation

- **Goal and setup:** satisfy the same downstream product using locally suitable
  inputs. The cached Wire table lists copper-based Wire and Iron Wire. At its
  stated standard rates, one Constructor makes 30 Wire/minute from 15 Copper
  Ingots/minute, or 22.5 Wire/minute from 12.5 Iron Ingots/minute. These are the
  table's figures, not measured 1.2 performance or a total-cost comparison. [S11]
- **Player verbs:** compare processes, choose a feedstock, locate forming stations,
  route input/output and retain or replace the existing line.
- **Constraints:** the same product does not make input stock, rate, upstream
  plant or transport interchangeable. In the proposed task, finite stock and
  physical station/service volume are hard limits; route length, spare capacity
  and retained useful material are soft objectives.
- **Solution families:** keep the process near its established supply; substitute
  abundant local material and provide more forming capacity; split production
  between routes. A lower nominal rate can still simplify a particular site if
  it removes a long feed. This inference does not rank whole factories. [S08], [S11]
- **Appeal:** inference: change the installation's structure rather than receive
  a numerically stronger machine with identical decisions.
- **Failure and recovery:** a new line can consume another order's feed or strand
  an old intermediate. Stop intake, finish or recover retained work and reconnect
  a working route. Configured paths must run unattended; carrying every batch is
  an errand. A universally dominant recipe would erase the intended choice.
- **Teaching and progression:** establish one working process and visible input
  use before offering another. A later order or newly accessible stock can change
  the useful choice; multiplying output alone adds no lesson.
- **Adaptation here:** original paper example: deliver 12 fasteners while keeping
  six common blanks for plates. Start with 12 common blanks and three scarce
  drawing blanks. One forming path converts one common blank to two fasteners;
  a two-stage drawing path converts one scarce blank to four. Common-only,
  scarce-only and mixed plans all succeed but retain different stock and occupy
  different routes. These illustrative names/ratios select no actual materials
  or game rules. Keep stations fixed and their tools mechanically driven. Place
  feeds at different heights only if this creates a routing/access decision.
- **Engineering risks:** one owner must retain recipe identity, reservations,
  in-process parts, completion and refunds across save/rejoin. A process change
  must not reinterpret or duplicate admitted material. Tooling/losses remain open.
- **Falsifier / smallest experiment:** use two small sites with different feed
  access and the same finite order. If one route always dominates or alternatives
  merely add clicks, revise the costs or reject the task.
- **Sources / related patterns:** S08, S11; Factorio `factorio-03/04` separately
  cover capacity and coproduct blockage. This card concerns input substitution
  competing with another finite order, not a claim of novel general mechanics.
- **Disposition:** candidate for a later stationary process-choice experiment;
  deferred below the physical opening. No recipe or technology is adopted.

## Pattern satisfactory-05: defer a choice while useful work continues

- **Goal and setup:** investigate a process without freezing the installation.
  The developer's 2024 preview identifies pending alternate-recipe selections
  obstructing further research as an earlier problem. Shipped 1.0 stores choices
  separately and permits one replacement pair per drive. This is documented
  presentation behavior, not observed current play. [S01], [S10]
- **Player verbs:** inspect options, keep a result pending, compare it with the
  factory and return later. The described replacement discards the earlier pair
  for that drive; it is not a free undo. [S10]
- **Constraints:** intelligible consequences and retained work matter more than
  an immediate answer. Source progression filters its offered pool; this does
  not settle our individual/team unlock model or justify random essential tools.
- **Solution families:** continue the known line while planning; try a separate
  small test installation; defer until related supply exists. Testing consumes
  space/material but reduces uncertainty; retaining the old line avoids disruption.
- **Appeal:** inference: choose how a capability fits a real factory, with enough
  information and time to compare consequences.
- **Failure and recovery:** disclose consumed research and discarded choices.
  Closing a comparison preserves the working factory. Finish, return or visibly
  retain a test station's stock before changing process. Repeated reroll/reload
  for essential random access would be a chore to avoid here, not a verified
  current source-game exploit.
- **Teaching and progression:** introduce optional alternatives after a complete
  material-to-product success. Explain live-process consequences before committing;
  an unfinished comparison can remain unfinished.
- **Adaptation here:** candidate compare-and-defer display for two known fixed
  forming methods. Pin sketches while the existing machine runs, then build a
  separate physical test using ordinary finite parts. A sketch grants no stock
  or completed technology. Keep mechanical operation and 3D construction without
  importing random research, electricity or a permanent unlock policy.
- **Engineering risks:** pending knowledge, tooling, custody and historical choices
  are distinct. The existing read-only example stays isolated; it cannot clone
  stock or quietly stop the factory clock. Team/unlock ownership remains DESIGN work.
- **Falsifier / smallest experiment:** open, pin and close a comparison while a
  fixed machine completes retained work, then resume a separate finite test. Any
  part expenditure, tooling replacement or lost work before a real admitted
  command contradicts the intended distinction.
- **Sources / related patterns:** S01, S10; `satisfactory-04` supplies the process
  choice, while Factorio `factorio-01/06` separate plans and fulfillment. This
  card addresses informed deferral rather than another blueprint tool.
- **Disposition:** retain compare-and-defer as a candidate presentation lesson;
  reject importing random unlock gambling as a prerequisite for this demo.

## Synthesis and proposed follow-ups

The immediate useful transfer is legible physical targeting and failure feedback,
which the current character/reach increment already owns. The later stationary
question worth testing is whether a vertical shared feed preserves a usable
service corridor better than a horizontal alternative. Do not add height solely
for presentation or copy the source game's electrical/remote-supply rules.

The second pass has one documented alternate-input example and an original
finite-stock comparison. It does not establish all upstream costs, actual recipe
switching/refunds or whole-game progression. Before a more complete study,
investigate representative process changeover and retained-work behavior.
Check the current fluid-height/flow model from primary developer or accessible
manual evidence and retain version differences. Deep simulation advice and old
water-tower exploits should not be imported from a cached guide.

The shipped 1.1 primary announcement explicitly removes the distance limit on
preview nudging. The cached Build Gun excerpt separately describes a finite
nominal range. Neither proves whether a final distant placement is
permitted, nor that our target should use either value. Our authority must check
the final requested target against the physical actor at admission. [S02], [S06]

No implementation task is created just to turn every card into work. These
candidates remain below the existing physical-character/stationary-loop priority.

## Coverage and review ledger

- Covered so far: dated 1.0/1.1 construction/logistics introductions and 1.2
  release context; five original stationary cards on service volume, startup
  versus capacity, construction with physical delivery, alternate input choices
  and informed deferral. The cached recipe and original paper process comparisons
  have explicit access/version limits; neither is an actual play result.
- Version readback: official publisher feed contains 1.2.4.1 on 2026-10-12;
  changelist/runtime build not tested. The 2025-04-01 experimental and 2025-06-10
  shipped 1.1 announcements are distinguished.
- Remaining: full current manual/control access; representative early-to-late
  production and alternate-recipe cases; exact failure/repair and unattended
  behavior; complete fluid/head-lift/version-change analysis. Cached recipe
  counts conflict, and several full manual pages were inaccessible. The study
  is not thorough and must not close on these five cards.
- Independent review: Ops accepted the original three-card partial note at
  `51c41e073553f619aed92a3a35faa7954dd894dd`, then separately reviewed and accepted
  the `a831c8f` successor's new cards and source qualifications for partial
  publication. Root reviewed the full successor and both review scopes before
  catalogue integration on 2026-10-19; the old verdict was not silently inherited.
- Exact note revision/check/publication: source freeze `a831c8f`; integration
  changes review/publication metadata only. Exact revision and source/index/hook
  results remain in the integration record.
- Closure: `factory-yau.8.2` remains in progress; recurring `factory-yau.8`
  remains open. Completing this partial pass is not retiring the research queue.
- Next owned action: resolve the missing current source/representative cases
  during safe waits for the higher-priority physical consumer implementation.

[S01]: https://steamstore-a.akamaihd.net/news/externalpost/steam_community_announcements/6242640076615256249
[S02]: https://steamstore-a.akamaihd.net/news/externalpost/steam_community_announcements/1801617199560021
[S03]: https://steamstore-a.akamaihd.net/news/externalpost/steam_community_announcements/1833968530900760
[S04]: https://steamstore-a.akamaihd.net/news/externalpost/steam_community_announcements/1846018067941164
[S05]: https://satisfactory.wiki.gg/wiki/Manifold
[S06]: https://satisfactory.wiki.gg/wiki/Build_Gun
[S07]: https://satisfactory.wiki.gg/wiki/Resource_Node
[S08]: https://satisfactory.wiki.gg/wiki/Hard_Drive
[S09]: https://satisfactory.wiki.gg/wiki/Head_lift
[S10]: https://steamstore-a.akamaihd.net/news/externalpost/steam_community_announcements/5875595438703071739
[S11]: https://satisfactory.wiki.gg/wiki/Wire
