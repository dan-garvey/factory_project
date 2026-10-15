# Delivery roadmap

This is a dependency plan derived from [DESIGN.md](DESIGN.md), not a new set of accepted gameplay choices or a production schedule. Detailed outcomes, acceptance evidence, prerequisites and source sections live in **Rust Beads**. The initial plan contains 47 scoped tasks across nine epics, including the ongoing roadmap and operations roots. Future discoveries should refine that ledger rather than multiply speculative implementation tasks.

The roadmap root is `factory-yau`; operations is `factory-wj6`. The first playable is a milestone, not completion of the whole roadmap. All required intended-game features remain visible, including those delivered later.

## Workstreams and immediately useful parallel work

| Subtree | Outcome | Ready proposal work |
| --- | --- | --- |
| `factory-yau.1` | First chapter and proposed release scope | `.1` concrete A/B/C production challenge; `.4` requirement-to-stage map and release alternatives |
| `factory-yau.2` | Shared-world learning, progression, logistics and resources | `.1` novice/advanced-team scenarios; `.4` construction-access alternatives |
| `factory-yau.3` | Portable authoritative rules and platform evidence | `.1` ownership boundary and bounded candidate-trial brief |
| `factory-yau.4` | Geometry and moving machinery | `.1` rotary/gantry/train-like, obstruction/isolation, passenger and transfer fixtures |
| `factory-yau.5` | Multiplayer and saves from the outset | `.1` authority/correction experiments; `.2` save/resume ownership/equivalence |
| `factory-yau.6` | Shared evidence, integration and player experience | `.1` neutral prototype witness and requirement traceability |
| `factory-yau.7` | Later intended-game scope | Deferred trains/autonomous acquisition, fluids/gases/controls, world/terrain, campaign/endings and numeric scale targets |
| `factory-wj6` | Project management and sole-machine operation | Resource admission, verified hourly delivery and continuing progenitor review |

Suffixes in the third column are relative to the subtree in the first. These are nine independent product/prototype proposal tasks; operations has its own work. Read the full task before claiming it. No ready proposal authorizes engine adoption, large downloads or game implementation.

```bash
br ready --type task --json
br ready --epic factory-yau --type task --json
br show factory-yau.3.1
br dep tree factory-yau.6.3
br dep cycles --json
```

## Convergence and decision gates

```text
core brief + common witness
    → bounded trial permission → authoritative headless + scene consumer
        → mechanics / two clients / save-resume / exact-count recovery in parallel
        → moving passengers, harvesting, transfer, correction and rejoin
        → combined candidate witness → platform evidence → production-stack decision

chapter challenge → layout tradeoffs + walkthrough + lasting-supply proposal
    → independent critique → first-chapter / bounded playable-scope decision
ownership scenarios → alternatives → ownership + check/delivery/consumption decision
    → accepted progression/logistics/resource interfaces

accepted production foundation + accepted playable contracts
    → source lifecycle / progression-deliveries / construction / teaching in parallel
    → chapter integration + FRESH combined verification
    → actual user play session → first-playable review
    → revisable first-release boundary → refine later delivery subtrees
```

The Beads edges, not this abbreviated drawing, are authoritative. Parent-child membership organizes scope; it does not require finishing an epic before its children. Design content, full campaign choices and final progression schemas do not block neutral technical probes. Candidate experiments need bounded permission, not the final engine decision whose evidence they are intended to produce.

Important gates:

- `factory-yau.3.2`: permission for a reversible candidate trial and its disk/work budget, not engine adoption.
- `factory-yau.1.6` and `factory-yau.2.3`: actual user choices for bounded playable scope and progression/logistics/quest-delivery rules. Silence is not approval.
- `factory-yau.3.5`: evidence-based provisional production stack decision. No language/engine is selected now.
- `factory-yau.6.2`: independent combined technical witness; isolated green demos are insufficient.
- `factory-yau.6.3`: first-chapter integration consumes separately scoped implementations (`.6`–`.9`) and reruns relevant combined evidence in the accepted production code.
- `factory-yau.6.4`/`.6.5`: actual user play and first-playable assessment. A paper walkthrough is not a playtest.
- `factory-yau.1.7`: a revisable first-release boundary informed by that play evidence. It does not prematurely block the first experiential prototype.

## Fidelity checks

The first chapter must demonstrate new processes for new products and optional redesign of earlier supply, not just higher output numbers. Test geometry-dependent scaling, cog direction and meaningful vertical construction. Old methods remain useful with practical drawbacks.

Moving factories must ultimately operate, harvest, transfer and carry players while moving; construction in motion is excluded. Early risk evidence includes a train-like constrained assembly and the candidate's actual player movement/collision/authority join, not only a parented transform. Broad connected-drivetrain stall and coupling isolation are accepted; independent pushing, detailed collision feedback, injury severity and docking rules remain deferred.

Precision controls can be probed early by developers without becoming mandatory early in player progression. Mechanical identity persists; electricity is excluded. Supply must eventually be fully automatable, without exhaustion-triggered unlocks or permanent manual-input traps. Location-sensitive logistics, exploration/base alternatives, ordinary inventory checks, inspectable teaching, multiple cooperative teams and independent learning remain intact.

The later subtree is deliberate deferred refinement, not permission to implement everything at once. It preserves required trains, autonomous finite acquisition, fluids/gases, later expressive controls, designed terrain/access/reshaping, off-site mystery commissions, semi-ending and harder multi-recipe-throughput true ending. Reserved manager-selection and leaderboard ideas remain uncommitted.

## Management

The original progenitor remains the integration/design-fidelity owner. [PROJECT_MANAGER.md](PROJECT_MANAGER.md) defines hourly review, explicit revision evidence, resource coordination, phone recovery and limitations. [CONTRIBUTING.md](CONTRIBUTING.md) remains the contributor contract. Accepted design changes go into DESIGN.md; project-management authority does not confer authority to choose unresolved gameplay on the user's behalf.
