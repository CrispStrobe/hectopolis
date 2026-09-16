# Feedback loops

Code: `packages/stadtbau_sim/lib/src/loops.dart`. The loops themselves are
PLAN §4.6; this file says how the game decides which one is currently doing the
most to the town (task T-504).

## What "strength" means

Each loop already exists in the simulation — nothing here adds behaviour. The
strength is a reading taken from quantities the model computes anyway, scaled
to 0–1 so the loops can be ranked against each other.

They are **different quantities**, so a strength is not a score and two loops
being at 0.4 does not make them equally important. The ranking answers one
question only: which loop is loudest right now.

| Loop | Polarity | Strength is |
|---|---|---|
| Crowding | balancing | the share of residential attractiveness that the noise and air terms are failing to deliver, averaged over residents |
| Tax base | reinforcing | monthly revenue ÷ (revenue + upkeep) |
| In-commuting | balancing | in-commuters ÷ local job capacity |
| Fragmentation | balancing | mean threat degradation over habitat cells |
| Regrowth | reinforcing | mean outstanding maturity over habitat cells |

## Why those readings

**Crowding.** Attractiveness is a weighted sum over noise, air, green, retail,
jobs and heat (`model/stocks.dart`). Population follows attractiveness, and
traffic drives noise and air. So the part of the weighted sum those two terms
fail to deliver is exactly what closes the loop back onto population. Weighting
by residents means an empty loud corner does not outvote a quiet full one.

**Tax base.** Residents and jobs pay income, property and business tax; every
tile costs upkeep. The ratio says how much of the month's money the town earns
from what it has built, which is what funds building more.

**In-commuting.** Jobs the local workforce cannot fill are taken from outside
and arrive by car, so the fraction filled from outside is the loop's own
variable, not a proxy for it.

**Fragmentation.** `model/habitat.dart` computes threat degradation per habitat
cell from roads and urban land within a radius. Its mean over habitat cells is
the pressure the loop applies.

**Regrowth.** A habitat tile is worth `biotopeStart` of its value the day it
appears and matures towards full value over `recoveryMonths`. What is
outstanding — `1 − maturity`, using the same curve as `model/habitat.dart` —
is the biodiversity and cooling the town is owed but has not been paid. It is
highest just after planting and decays over years, which is the delay the loop
is about.

Using the maturity curve **including `biotopeStart`** matters: without it a
fresh meadow reads as owing its entire value, when the model already counts
almost half of it. The 16×16 sandbox starts as young meadow, so this is the
difference between "regrowth 1.0" and the correct 1 − 0.45.

## Limits and next steps

- Strength is instantaneous. A loop that is about to dominate looks quiet.
- Polarity is fixed per loop, though the tax-base loop turns balancing once
  upkeep outgrows revenue; only its strength moves, not its label.
- No loop-gain computation: this ranks loops, it does not simulate them
  competing. Proper dominance analysis would linearise the system each tick.

## References

- Sterman (2000), *Business Dynamics*: loop dominance and shifting dominance
- The per-field sources in `noise.md`, `air.md`, `biodiversity.md`, `economy.md`
