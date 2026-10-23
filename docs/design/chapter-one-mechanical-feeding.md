# Chapter 1 mechanical feeding candidates

This note records small, reversible geometry rules for `factory-yau.1.10.17.1`.
They are design choices for future native and ordinary-scene work, not claims
about the current runtime or requirements for the first plate. The first plate
remains hand-fed. `factory-yau.1.10.16.4` owns broad-item carrier behavior and
`factory-yau.1.10.16.6` owns the raised gravity route; this note gives them one
common fit question to answer.

## Shared fit rule

- Use the existing world origin and one construction denominator. One workcell
  edge is four quarter-grid steps in X, Y or Z; a foundation level is therefore
  four height steps. Every guide, support, inlet and outlet snaps to that grid.
  No tool gets a separate height increment. A normal stock piece or plate has
  a 1 × 1 horizontal footprint; the proposed broad sheet has a 2 × 2 footprint
  and keeps one item identity until cutting. One thickness is enough here.
- A straight channel has a cardinal X or Z travel axis, a declared clear width
  in whole workcells, a supported floor across that width, and an entry and
  exit face. Width 1 admits a one-cell item; width 2 can admit a two-cell item
  only if the item's orientation and the complete swept footprint fit. A bend
  needs the same swept-footprint test around its corner. A carrier or receiving
  tool must expose a matching aperture and free landing area. Rotating a broad
  sheet is a separate physical action, not an automatic result of reaching a
  narrower channel.
- A level guide aligns and supports an item, but needs a push, roller or
  mechanical drive to advance it. A gravity guide descends by a whole number
  of shared height steps between grid-aligned endpoints. Its down direction
  must match travel, its complete swept footprint needs support and headroom,
  and its lower receiver must be present and free. A gap without a landing
  surface is not a transfer permission. The exact useful slope and speed can
  be tuned in implementation; downward height alone does not move an item.
- A channel never recognizes a recipe or changes material form. A transfer is
  permitted only when the next segment or receiver fits the item's current
  footprint and orientation and has capacity. The authoritative owner changes
  once at the handoff. On a refusal or stop, the same item remains accessible
  at its prior owner with its identity, quantity and orientation intact. Save
  and rejoin retain the owner and any bounded in-segment position; neither
  creates a second loose item nor silently finishes the transfer.

The player reads the rule from the visible width, rails, support and clear
mouth of the route. Separate variants for every product would hide the shared
fit decision; a 2 × 2 sheet and any later broad workpiece use the same test.
Full loose-pile physics, arbitrary slope angles and per-recipe channel tokens
are outside this candidate.

## Two useful arrangements

| Use | Valid route | Refusal and recovery |
| --- | --- | --- |
| Feed a small stock piece to an anvil | A one-wide level guide points at a clear press inlet. A hand push or driven roller moves one stock piece into the free work position; the guide may be rotated to another open side of the same press. | An outlet aimed beside the inlet, an occupied anvil or a blocked guide stops the piece at its last owner. Moving the obstacle or turning the guide permits the same piece to continue. |
| Move one broad sheet from a raised former to a lower shear | A two-wide supported slide starts at the clear upper outlet, descends to a matching two-wide landing, and meets the shear's broad inlet. The sheet stays one oriented item. After shearing, individual plates may enter one-wide belts. | A one-wide belt, sideways broad sheet, reverse slope, missing landing support or occupied shear refuses the handoff. The sheet stays at the upper outlet or last supported segment for pickup or rerouting; no plate appears early. |

These routes make a real layout choice: a driven level guide spends power and
keeps elevation, while a gravity slide spends vertical room and requires a
lower receiver. Both use the same fit and custody rule. A broad gantry carrier
from `factory-yau.1.10.16.5` can also pass this fit test with its own supported
deck and motion; the guide design does not implement or replace that carrier.
