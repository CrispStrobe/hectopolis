# Commuting and traffic

Code: `packages/stadtbau_sim/lib/src/model/commute.dart`. Parameters: `commute.*`.

## Model

1. **Workers.** `W_i = P_i · 0.52` (Destatis: employed persons ÷ population).
2. **Local share.** `f_local = min(1, J_total / W_total)`; the rest commute out
   (15 km, MiD 2017 mean for out-commuters, initial estimate). Unfilled jobs
   are taken by in-commuters (`J_total − W_total`).
3. **Distribution.** Local workers of cell `i` go to job cell `j` in proportion
   to `jobs_j · exp(−d_ij / 2 km)` (gravity kernel, shared with job access).
4. **Mode share by distance** (MiD 2017 Ergebnisbericht and MiD 2017 Analysen
   zum Rad- und Fußverkehr, rounded):

   | one-way distance | walk | bike | car |
   |---|---|---|---|
   | ≤ 1 km | 0.55 | 0.20 | 0.25 |
   | 1–3 km | 0.15 | 0.35 | 0.50 |
   | > 3 km and external | 0.02 | 0.13 | 0.85 |

5. **Traffic assignment.** Car trips (× 2 for the return) enter the road
   network at the nearest main road within 300 m of origin and destination and
   follow the shortest road path (breadth-first search over 4-connected road
   cells). External trips leave via the nearest border road. Every main road
   carries 2 000 vehicles/day of through traffic as a baseline.
6. **Outputs.** Vehicles/day per road cell (feeds noise and air), mean commute
   distance and car share per residential cell, total car-km per weekday
   (× 20 days × 12 months × 0.15 kg CO₂/km for the climate balance).

## Feedback loops

- More jobs than housing → in-commuters → traffic, noise, pollution.
- Housing without nearby jobs → long car commutes → traffic and CO₂.
- Housing without a main road within 300 m → attractiveness × 0.7.

## References

- Mobilität in Deutschland 2017, Ergebnisbericht (BMVI/infas):
  https://www.mobilitaet-in-deutschland.de/archive/pdf/MiD2017_Ergebnisbericht.pdf
- MiD 2017, Analysen zum Rad- und Fußverkehr:
  https://www.mobilitaet-in-deutschland.de/archive/pdf/MiD2017_Analyse_zum_Rad_und_Fussverkehr.pdf
- Destatis, Erwerbstätigenrechnung
- Umweltbundesamt, Emissionsdaten Pkw (≈ 150 g CO₂/km Flottenmittel)

## Public transport and cycling (T-502 follow-up, 2026-09-17)

`tram_stop` and `cycle_path` shipped with no mechanism: they acted only through
their land cover, and carried a placeholder negative `co2PerHaYear` because the
traffic they replace had nowhere to go. They now act where they should.

### A substitution, not a fourth mode

The mode share bins are walk, bike and car; there is no public-transport mode,
so the car share absorbs what would be transit. Rather than add a mode and
recalibrate every bin, a stop or a route **takes a share of a cell's car trips
away**:

```
transit = mean(transitAccess[origin], transitAccess[destination]) · transitCarReduction
cycle   = mean(cycleAccess[origin],   cycleAccess[destination])   · cycleCarReduction
                                                     … and 0 beyond cycleCompetitiveKm
cars   ·= max(minCarShareFactor, 1 − transit − cycle)
```

Everything downstream — traffic on the road network, noise, air, CO₂ — follows
from the reduced car count without any further change.

`transitAccess` and `cycleAccess` are 1 on the tile and fall linearly to 0 at
their radius, so a stop helps its neighbourhood rather than only its own cell.
A trip needs the infrastructure **at both ends**, which is why the two ends are
averaged; the external commute is served by a stop but not by a cycle route,
being far beyond the competitive distance.

`minCarShareFactor` keeps at least half of a cell's car trips: some journeys
are not served by either, and a model that can reach zero cars invites a
scenario that is won by tiling stops.

### Where the numbers come from

Anchored on the MiD 2017 national modal split — 22 % on foot, 11 % bicycle,
43 % car driver, 14 % car passenger, **10 % public transport**. That 10 % mixes
served and unserved places, so a stop in walking distance taking up to a
quarter of a cell's car trips puts a fully served map above the national
average without reaching the share of a large city. The cycling figure is of
the order of the 11 % bicycle share, and of this model's own bins, which
already peak cycling at 21 % between 1 and 1.5 km.

The stop catchment of 400 m is ordinary planning practice for tram and light
rail. These are **design values, not measured elasticities**, and say so in
their `source` fields.

### Limits

- No timetable, capacity, line or network: a stop is useful in isolation, and
  two stops do not connect to each other.
- No fare, no operating subsidy. A stop costs its build and upkeep only.
- The car trips removed do not reappear as transit trips anywhere: they simply
  stop existing, so the commute distance and mode statistics describe the cars
  that remain rather than all travel.
- Cycling's cutoff is a hard distance rather than a taper.
