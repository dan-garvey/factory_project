# Delivery roadmap

This is a dependency plan derived from [DESIGN.md](DESIGN.md), not a new set of accepted gameplay choices or a production schedule. Detailed outcomes, acceptance evidence, prerequisites and source sections live in **Rust Beads**. The initial plan contains 47 scoped tasks across nine epics, including the ongoing roadmap and operations roots. Future discoveries should refine that ledger rather than multiply speculative implementation tasks.

The roadmap root is `factory-yau`; operations is `factory-wj6`. The first playable is a milestone, not completion of the whole roadmap. All required intended-game features remain visible, including those delivered later.

Current user objective (2026-10-15 UTC): a demoable **first chapter over the next few days**, with placeholder assets and rough edges acceptable. The user explicitly delegates routine reversible design/technical choices and asks the PM to keep agents moving without waiting for decisions; the user will course-correct. This prioritizes an integrated, runnable experience over proposal volume. Record choices and evidence rather than converting drafts into permanent canon. Detailed task evidence lives in the private shared Beads tracker with separate gist backup, not public history.

The user clarified the order: **basic collector → machine → product first**; complete starter machines are acceptable. Player-built motion is welcome later in chapter 1, after the basics work and receive feedback. The first demo does not have to prove every intended-game differentiator. The old motion-first packet recommendation was not an accepted requirement.

## Workstreams and immediately useful parallel work

| Subtree | Outcome | Work boundaries; inspect Beads for live readiness |
| --- | --- | --- |
| `factory-yau.1` | First chapter and proposed release scope | `.6` delegated opening defaults recorded; `.4` later stage map; earlier A/B/C proposals are optional later inputs |
| `factory-yau.2` | Shared-world learning, progression, logistics and resources | `.1` novice/advanced-team scenarios; later ownership, construction-access and lasting-supply decisions |
| `factory-yau.3` | Authoritative rules and platform evidence | `.2` delegation/bounded first baseline recorded; `.3` sandbox/shared headless/3D path in progress; coupling limits explicit |
| `factory-yau.4` | Geometry and moving machinery | `.1` rotary/gantry/train-like, obstruction/isolation, passenger and transfer fixtures |
| `factory-yau.5` | Multiplayer and saves from the outset | `.7` parallel harness → `.3` real two-client validation; `.4` basic continuation; moving-world work stays in `.5`/`.6` |
| `factory-yau.6` | Shared evidence, integration and player experience | `.12` parallel interactive consumer → `.10` integrated demo → `.5` next increment; `.11` actual user feedback when available, not an idle gate |
| `factory-yau.7` | Later intended-game scope | Deferred trains/autonomous acquisition, fluids/gases/controls, world/terrain, campaign/endings and numeric scale targets |
| `factory-wj6` | Project management and sole-machine operation | Resource admission, verified hourly delivery and continuing progenitor review |

Suffixes in the third column are relative to the subtree in the first. This is a workstream map, not a current ready-task count. Read the full task before claiming it. No ready proposal authorizes engine adoption, large downloads or game implementation.

```bash
br ready --type task --json
br ready --epic factory-yau --type task --json
br show factory-yau.3.1
br dep tree factory-yau.6.3
br dep cycles --json
```

## Convergence and decision gates

```text
delegated opening defaults + bounded reversible environment
    → shared headless + 3D rules path
        ↔ parallel interactive consumer and stationary two-client harness
        → minimal real two-client and basic save/continuation checks
    → integrated basic collector / transport / processor / product demo
    → independent review and next scoped increment, possibly chapter-1 motion
        ← incorporate actual user feedback when available (separately tracked)

separate early architecture-risk / production-adoption track:
core brief + common witness
    → bounded trial permission → authoritative headless + scene consumer
        → mechanics / two clients / save-resume / exact-count recovery in parallel
        → moving passengers, harvesting, transfer, correction and rejoin
        → combined candidate witness → platform evidence → production-stack decision

earlier chapter/layout/walkthrough/supply proposals
    → optional inputs to later chapter decisions, not opening prerequisites
ownership scenarios → alternatives → ownership + check/delivery/consumption decision
    → accepted progression/logistics/resource interfaces

basic-loop review + accepted production foundation + scoped extension contracts
    → source lifecycle / progression-deliveries / construction / teaching in parallel
    → broader chapter integration + FRESH applicable combined verification
    → later extension play session

opening review + platform evidence → revisable first-release boundary
    → refine later delivery subtrees
```

The Beads edges, not this drawing, are authoritative. Parent-child membership organizes scope; it does not require completing an epic first. Routine reversible choices are delegated, not new user-answer gates. A component may develop against an agreed in-flight API, but integration acceptance needs the actual shared implementation; do not create duplicate authority to fill time. Full campaign/progression choices do not block neutral probes. Refine later edges to the chosen extension, not every old proposal. Actual user play remains unclaimed until it happens, without blocking other verified work.

Important gates:

- `factory-yau.3.2`: completed record of delegated environment evaluation and the named bounded first sandbox; not production adoption.
- `factory-yau.1.6`: completed delegated opening defaults; implement them without another routine approval card.
- `factory-yau.2.3`: later ownership/check/delivery choices for systems that exercise them; scoped revisable decisions may be delegated, not silently made permanent.
- `factory-yau.3.5`: evidence-based revisable production-direction decision, distinct from the sandbox and not already satisfied by delegation. No production stack is selected now.
- `factory-yau.6.2`: independent combined technical witness; isolated green demos are insufficient.
- `factory-yau.6.12` and `.5.7`: separately owned opening consumer and network harness, parallel with `.3.3` using an agreed model API. Final tests must consume that real shared model.
- `factory-yau.6.10`/`.6.5`: integrated basic demo then independent review/next increment. Needs `.6.12`, `.3.3`, stationary `.5.3` and basic save `.5.4`, not full moving-world `.6.2` or production adoption `.3.5`.
- `factory-yau.6.11`: actual user play, incorporated when available; not a prerequisite for `.6.5` or all further work. Agent scripts cannot close it.
- `factory-yau.6.3`: broader integration after basic-loop review; retains the production and motion-risk track, with `.6`–`.9` scopes/edges refined to the chosen extension. It is not the first-feedback gate.
- `factory-yau.6.4`: later chapter-extension play observations, not a mandatory crowded vertical/motion factory before opening feedback. A paper walkthrough is not a playtest.
- `factory-yau.1.7`: a revisable first-release boundary informed by that play evidence. It does not prematurely block the first experiential prototype.

## Fidelity checks

The opening must first make basic placement, physical transport and processing understandable and usable. Player-built motion may follow later in chapter 1. Across progression, preserve new processes for new products and optional redesign of earlier supply, not just higher output numbers. Test geometry-dependent scaling, cog direction and meaningful vertical construction as those systems are introduced; do not require all of them for the initial demo. Old methods remain useful with practical drawbacks.

Moving factories must ultimately operate, harvest, transfer and carry players while moving; construction in motion is excluded. Early risk evidence includes a train-like constrained assembly and the candidate's actual player movement/collision/authority join, not only a parented transform. Broad connected-drivetrain stall and coupling isolation are accepted; independent pushing, detailed collision feedback, injury severity and docking rules remain deferred.

Precision controls can be probed early by developers without becoming mandatory early in player progression. Mechanical identity persists; electricity is excluded. Supply must eventually be fully automatable, without exhaustion-triggered unlocks or permanent manual-input traps. Location-sensitive logistics, exploration/base alternatives, ordinary inventory checks, inspectable teaching, multiple cooperative teams and independent learning remain intact.

The later subtree is deliberate deferred refinement, not permission to implement everything at once. It preserves required trains, autonomous finite acquisition, fluids/gases, later expressive controls, designed terrain/access/reshaping, off-site mystery commissions, semi-ending and harder multi-recipe-throughput true ending. Reserved manager-selection and leaderboard ideas remain uncommitted.

## Continuing work selection

Workers own continuing workstream queues and may create/refine/claim bounded follow-ups and coordinate peer reviews without a new PM dispatch. Follow the [autonomous queue contract](CONTRIBUTING.md#autonomous-workstream-queues), search for duplicate work, and keep actual dependencies in Beads. A frozen candidate need not idle its author; advance another useful ready outcome in a separate linked worktree. The PM retains cross-stream prioritization, resource coordination and serialized main publication.

The next increment after shared-opening integration pairs a normal shared-play launcher (`factory-yau.5.13`, independent review `.6.24`) with an optional player-configured mechanical workshop (`factory-yau.6.23`, review `.6.25`). The latter explores motion and arrangement without replacing the basic production opening or pretending non-consuming geometry contacts are produced inventory. These are scoped experiments, not proof of a complete chapter, user play or a production-stack decision. Read the live Beads for current status and subsequent work rather than treating this snapshot as the whole queue.

## Management

The original progenitor remains the integration/design-fidelity owner. [PROJECT_MANAGER.md](PROJECT_MANAGER.md) defines hourly review, explicit revision evidence, resource coordination, phone recovery and limitations. [CONTRIBUTING.md](CONTRIBUTING.md) remains the contributor contract. Accepted design changes go into DESIGN.md; project-management authority does not confer authority to choose unresolved gameplay on the user's behalf.
