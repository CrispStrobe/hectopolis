# Access: green space, shopping, jobs

Code: `packages/stadtbau_sim/lib/src/model/access.dart`. Parameters: `access.*`,
`tiles.*.greenWeight`, `tiles.commercial.retailFloorM2`, `tiles.*.jobsPerHa`.

## Green access (recreation)

WHO recommends green space of at least 0.5 ha within 300 m of every home; the
3-30-300 rule (Konijnendijk 2021) uses the same 300 m. Every green tile is
1 ha, so the test is: is there a green tile within 3 tiles (Euclidean)?

`green_i = clamp(max_j w_j + bonus, 0, 1)` with recreational weights
park 1.0, forest 0.9, water 0.7, meadow 0.6, cropland 0.3 and a variety bonus
of 0.2 when at least 3 green tiles are within reach.

## Shopping access (Huff model)

Retail supply `S_j = 2 000 m²` of sales floor per commercial tile (20 % of the
plot), demand 1.4 m² per resident (HDE Zahlenspiegel). Huff (1963):

`A_i = Σ_j S_j / max(d_ij, 0.5)^λ`, `λ = 2`, within 700 m (BBSR Nahversorgung:
fußläufig 500–700 m).

`retail_i = clamp(A_i / A_ref, 0, 1)` with `A_ref = 2 000 / 3² ≈ 222`, so one
commercial tile at 300 m gives a full score.

## Job access (gravity)

`J_i = Σ_j jobs_j · exp(−d_ij / 2 km)`, `jobAccess_i = clamp(J_i / 400, 0, 1)`.
The 2 km decay is a local-access scale (MiD 2017 median commute is longer, but
the indicator is about jobs reachable without a long trip).

**The 2 km is a design value, and since 2026-10-26 it is only this one.**
It used to double as the destination-choice gravity of the commute model, and
that is where the two came apart: German commutes decay over about 10 km
(`commute.md`, `commute.commuteDecayM`), while on a 1.6–6.4 km map a 10 km
kernel gives every cell nearly the same job access, and the overlay would show
nothing. The indicator asks which jobs are close, the commute asks where people
actually go; they are now two parameters because they are two questions.

## References

- WHO Regional Office for Europe (2016): Urban green spaces and health.
- Konijnendijk (2021): The 3-30-300 rule for urban forestry and greener cities.
- Huff (1963): A probabilistic analysis of shopping center trade areas.
- HDE Handelsverband Deutschland, Zahlenspiegel (Verkaufsfläche je Einwohner).
- BBSR (2013 ff.), Nahversorgung in ländlichen Räumen / Innenentwicklung.
