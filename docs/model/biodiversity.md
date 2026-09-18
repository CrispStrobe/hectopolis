# Habitat quality and biodiversity

Code: `packages/stadtbau_sim/lib/src/model/habitat.dart`. Parameters:
`habitat.*`, `tiles.*.biotopeValue`, `biotopeStart`, `recoveryMonths`.

## Model

1. **Base habitat** for nature and urban-green tiles:
   `H_i = (biotopeValue_i / 24) · maturity_i` with the BKompV Anlage 2 value
   (see `tiles.md`) and maturity growing with tile age.

2. **Threat degradation** after the InVEST Habitat Quality model. Each threat
   land use `r` has weight `w_r` and maximum distance `d_max,r` with linear
   decay:

   `D_i = clamp(Σ_r Σ_y w_r · (1 − d_iy / d_max,r) / 4, 0, 1)`

   (four adjacent full-weight threats saturate). Threats: road 1.0 / 300 m,
   industry 0.8 / 500 m, commercial 0.6 / 300 m, apartment blocks 0.5 / 200 m,
   detached housing 0.3 / 200 m.

   **Where those ten numbers come from (T-103).** The weights had been cited to
   an "InVEST HQ sample threat table" that does not say what was claimed: the
   user guide's example lists a dirt road at 0.1, a paved road at 0.4 and
   agriculture at 1.0, and has no urban row at all. What the guide does say is
   the useful part — **weights are normalised before use, so only their ratios
   carry meaning**; two weight sets behave identically unless the relative
   differences between them differ. The ordering road > industry > commercial >
   apartment blocks > detached housing is therefore the whole content of the
   weight column, and it is a design decision, now labelled as one.

   The distances could not be taken from InVEST either: its example works at
   landscape scale (2 km, 4 km, 8 km), and a 4 km threat would blanket a whole
   municipal map on a 100 m grid.

   **road / 300 m is the one that could be grounded.** Forman & Deblinger (2000)
   measured a road-effect zone averaging about 600 m beside a four-lane suburban
   highway. Reijnen & Foppen derive species-specific disturbance distances from
   traffic noise: 20–1700 m at 5 000 vehicles a day, 65–3530 m at 50 000. A game
   road carries 10 000 a day and is not a four-lane highway, so 300 m sits in
   the lower part of those spans, which is where it belongs.

   The four settlement distances (500 m industry, 300 m commercial, 200 m
   housing) remain design: they order operational noise and light above mere
   human presence, and nothing in the literature transfers directly to a
   hectare-resolution municipal model.

   `Q_i = H_i · (1 − D_i^z / (D_i^z + k^z))`, `z = 2.5`, `k = 0.5` (InVEST
   defaults).

3. **Connectivity.** Habitat tiles form patches by 8-neighbourhood. With
   quality-weighted patch areas `A_p = Σ_{i∈p} Q_i`, the effective mesh size
   (Jaeger 2000) is `m_eff = Σ_p A_p² / A_total` and connectivity
   `c = m_eff / A_total ∈ (0, 1]` (1 = one patch).

4. **Biodiversity index.** Species–area relation `S ∝ A^z` with `z = 0.30`
   (habitat islands: 0.25–0.35):

   `B = 100 · (A_total / N)^0.30 · (0.5 + 0.5 · c)`.

## Behaviour

- All-forest map, mature: ≈ 92. Cutting it with a road cross: −15 to −20.
- Suburb with meadows in between: ≈ 40; dense quarter with one park: ≈ 26.
- Newly planted forest starts near a Vorwald value and reaches full value
  after 20 years, so afforestation pays off with delay.

## References

- BKompV Anlage 2 (biotope values): https://www.gesetze-im-internet.de/bkompv/anlage_2.html
- InVEST User Guide, Habitat Quality model (threat decay, half-saturation)
- Forman & Deblinger (2000): The ecological road-effect zone of a Massachusetts (U.S.A.) suburban highway. Conservation Biology 14, 36–46.
- Reijnen & Foppen: Disturbance by traffic of breeding birds — evaluation of the effect and considerations in planning and managing road corridors. Biodiversity and Conservation.
- Jaeger (2000): Landscape division, splitting index, and effective mesh size.
  Landscape Ecology 15, 115–130.
- MacArthur & Wilson (1967): The Theory of Island Biogeography; Arrhenius (1921).
