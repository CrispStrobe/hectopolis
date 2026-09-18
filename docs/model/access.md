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

**`access.jobDecayM` does double duty**, and anyone retuning it should know:
the same kernel is the destination-choice gravity of the commute model
(`commute.md`), where it decides how far a worker is willing to look for a job.
So a larger decay does not only widen the job-access overlay — it lengthens
every commute and shifts the mode split with it. The two roles are defensible
on the same number, but they are not the same question, and splitting them into
two parameters is the honest move if they ever need to move apart.

`computeAccess` and `computeCommute` therefore evaluate the same sum over the
same job cells, twice per tick. Sharing it would save roughly a tenth of the
field pass and couple the two modules to an invariant nothing enforces; at
7.4 ms for the whole pass it is not worth the coupling today, and this note
exists so the option is a choice rather than an oversight.

## References

- WHO Regional Office for Europe (2016): Urban green spaces and health.
- Konijnendijk (2021): The 3-30-300 rule for urban forestry and greener cities.
- Huff (1963): A probabilistic analysis of shopping center trade areas.
- HDE Handelsverband Deutschland, Zahlenspiegel (Verkaufsfläche je Einwohner).
- BBSR (2013 ff.), Nahversorgung in ländlichen Räumen / Innenentwicklung.
