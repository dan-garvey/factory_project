# Delivery roadmap

This is a dependency plan derived from [DESIGN.md](DESIGN.md), not a new set of accepted gameplay choices or a production schedule. Detailed outcomes, acceptance evidence, prerequisites and source sections live in **Rust Beads**. The initial plan contains 47 scoped tasks across nine epics, including the ongoing roadmap and operations roots. Future discoveries should refine that ledger rather than multiply speculative implementation tasks.

The roadmap root is `factory-yau`; operations is `factory-wj6`. The first playable is a milestone, not completion of the whole roadmap. All required intended-game features remain visible, including those delivered later.

Current user objective (2026-10-15 UTC): a demoable **first chapter over the next few days**, with placeholder assets and rough edges acceptable for direct feedback on the initial systems. This prioritizes an integrated, runnable chapter rather than proposal volume. Open gameplay and engine choices still need explicit decisions; this objective is not proof of delivery or automatic approval of existing drafts. Detailed task evidence now lives in the private, shared, Git-ignored Beads tracker with separate gist backup, not in the public repository history.

The user clarified the order: **basic collector → machine → product first**; complete starter machines are acceptable. Player-built motion is welcome later in chapter 1, after the basics work and receive feedback. The first demo does not have to prove every intended-game differentiator. The old motion-first packet recommendation was not an accepted requirement.

## Workstreams and immediately useful parallel work

| Subtree | Outcome | Work boundaries; inspect Beads for live readiness |
| --- | --- | --- |
| `factory-yau.1` | First chapter and proposed release scope | `.6` bounded opening rules; `.4` requirement-to-stage map; earlier A/B/C proposals are optional later inputs |
| `factory-yau.2` | Shared-world learning, progression, logistics and resources | `.1` novice/advanced-team scenarios; later ownership, construction-access and lasting-supply decisions |
| `factory-yau.3` | Portable authoritative rules and platform evidence | `.2` named trial permission; `.3` shared core/scene path; later evidence-based stack adoption |
| `factory-yau.4` | Geometry and moving machinery | `.1` rotary/gantry/train-like, obstruction/isolation, passenger and transfer fixtures |
| `factory-yau.5` | Multiplayer and saves from the outset | `.1` stationary authority/concurrency contract; `.3` two clients; `.4` basic continuation; moving-world specification/evidence stays in `.5`/`.6` |
| `factory-yau.6` | Shared evidence, integration and player experience | `.10` basic demo → `.11` user feedback → `.5` next investment; `.2` broader risk witness and `.3` later integration remain separate |
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
bounded opening rules + expressly approved candidate/demo environment
    → shared headless + 3D rules path
        → minimal stationary two-client and basic save/continuation checks
    → basic collector / transport / processor / product demo
    → actual opening play feedback → review and next-investment decision
        → refine a later chapter-1 extension, possibly player-built motion

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

basic-loop feedback + accepted production foundation + accepted extension contracts
    → source lifecycle / progression-deliveries / construction / teaching in parallel
    → broader chapter integration + FRESH applicable combined verification
    → later extension play session

opening review + platform evidence → revisable first-release boundary
    → refine later delivery subtrees
```

The Beads edges, not this abbreviated drawing, are authoritative. Parent-child membership organizes scope; it does not require finishing an epic before its children. Design content, full campaign choices and final progression schemas do not block neutral technical probes. Candidate experiments need bounded permission, not the final engine decision whose evidence they are intended to produce. A basic playable candidate also needs express scope permission; it is not automatically covered by permission for an unrelated spike. Refine later integration edges to match the chosen extension before dispatch, rather than treating every old proposal as mandatory chapter content.

Important gates:

- `factory-yau.3.2`: permission for a reversible candidate trial and its disk/work budget, not engine adoption.
- `factory-yau.1.6`: actual user choices for the minimum bounded opening rules; basic shape/order already clarified. Full later chapter content does not have to be selected first.
- `factory-yau.2.3`: still-open ownership/check/delivery decisions for systems that exercise them; do not invent a shared progression model in the opening.
- `factory-yau.3.5`: evidence-based provisional production stack decision. No language/engine is selected now.
- `factory-yau.6.2`: independent combined technical witness; isolated green demos are insufficient.
- `factory-yau.6.10`/`.6.11`/`.6.5`: basic demo, actual initial user feedback, then next-investment assessment. This path needs `.3.3`, stationary `.5.3` and basic save `.5.4`, not full moving-world `.6.2` or production adoption `.3.5`. Rerun applicable checks in the integrated demo.
- `factory-yau.6.3`: broader integration after basic-loop feedback; retains the production and motion-risk track, with `.6`–`.9` implementation scopes/edges refined to the extension actually chosen. It is not the first-feedback gate.
- `factory-yau.6.4`: later chapter-extension play observations, not a mandatory crowded vertical/motion factory before opening feedback. A paper walkthrough is not a playtest.
- `factory-yau.1.7`: a revisable first-release boundary informed by that play evidence. It does not prematurely block the first experiential prototype.

## Fidelity checks

The opening must first make basic placement, physical transport and processing understandable and usable. Player-built motion may follow later in chapter 1. Across progression, preserve new processes for new products and optional redesign of earlier supply, not just higher output numbers. Test geometry-dependent scaling, cog direction and meaningful vertical construction as those systems are introduced; do not require all of them for the initial demo. Old methods remain useful with practical drawbacks.

Moving factories must ultimately operate, harvest, transfer and carry players while moving; construction in motion is excluded. Early risk evidence includes a train-like constrained assembly and the candidate's actual player movement/collision/authority join, not only a parented transform. Broad connected-drivetrain stall and coupling isolation are accepted; independent pushing, detailed collision feedback, injury severity and docking rules remain deferred.

Precision controls can be probed early by developers without becoming mandatory early in player progression. Mechanical identity persists; electricity is excluded. Supply must eventually be fully automatable, without exhaustion-triggered unlocks or permanent manual-input traps. Location-sensitive logistics, exploration/base alternatives, ordinary inventory checks, inspectable teaching, multiple cooperative teams and independent learning remain intact.

The later subtree is deliberate deferred refinement, not permission to implement everything at once. It preserves required trains, autonomous finite acquisition, fluids/gases, later expressive controls, designed terrain/access/reshaping, off-site mystery commissions, semi-ending and harder multi-recipe-throughput true ending. Reserved manager-selection and leaderboard ideas remain uncommitted.

## Management

The original progenitor remains the integration/design-fidelity owner. [PROJECT_MANAGER.md](PROJECT_MANAGER.md) defines hourly review, explicit revision evidence, resource coordination, phone recovery and limitations. [CONTRIBUTING.md](CONTRIBUTING.md) remains the contributor contract. Accepted design changes go into DESIGN.md; project-management authority does not confer authority to choose unresolved gameplay on the user's behalf.
