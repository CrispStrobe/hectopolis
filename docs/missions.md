# Missions: what the audit checks, and what it found

Tool: `packages/stadtbau_sim/tool/learning_audit.dart`, run as a stage of
`tools/check.sh learning` and in CI. Pure Dart — no browser, no Playwright.

```bash
cd packages/stadtbau_sim
dart run tool/learning_audit.dart              # 8 paths per mission, the CI setting
dart run tool/learning_audit.dart --paths 60   # a deep pass, ~360 played paths
```

## Why it exists

Mission text is not strings in widgets. Every piece of it is an ICU `select`
keyed by a stable id — `missionBeatTitle`, `challengeName`,
`learningConceptCause`, `missionPredictionPrompt` and nineteen more — and
**ICU has no exhaustiveness check**. An id with no branch does not fail the
build and does not fail at run time: it renders the `other` branch and looks
like working copy. `tools/i18n_lint.dart` compares the *keys* in the two ARB
files, so it cannot see this at all; a German build can fall back where the
English one does not.

The second half is a different failure. A beat that never fires and a medal
the game can never award are dead content that no unit test notices, because
no unit test plays a level.

## The two halves

**Copy coverage** enumerates every id the level data and the model enums
actually produce — 205 of them across 23 localized keys — and checks each
against the branches present in both `app_en.arb` and `app_de.arb`. It also
reports branches that exist in one file and not the other, which is the exact
gap the key-parity lint leaves open.

**Reachability** plays every mission along many randomised paths *and* along
its worked plan from `tool/level_plans.dart` — the same plan
`test/level_solutions_test.dart` asserts is a three-star solution. Random play
is a fuzzer: it reaches triggers a plan happens to miss, but it cannot tell a
hard challenge from an impossible one. The worked plan answers that.

It models the game's end faithfully, which matters more than it sounds:
`GameController._recompute` fires the end screen at the **first** moment every
goal is met and banks the stars and the medals *then*. That moment can arrive
while the player is still placing tiles. A harness that waited until the end of
the plan would credit medals the player is never given.

## Severity

**Problems** fail the run and are deterministic: a missing ICU branch, a branch
in one language and not the other, a level with no worked plan, a plan that no
longer solves, a goal whose hint can name no tile, a medal that is satisfied at
some point but never at the moment the game awards it.

**Notes** do not fail and ask for a human: a beat nobody happened to reach, a
challenge no sample met, a mission with no teaching content. Sampling is why —
a note at `--paths 8` may simply disappear at `--paths 60`.

## What the first full pass found (2026-09-18, 360 paths)

Copy coverage was **clean**: all 205 ids have a branch in both languages, and
the two files carry identical branch sets. Nothing silently falls back today.
(The check was verified by deleting one German branch: the audit reported it
while `i18n_lint` still said ok.)

The reachability half produced no problems and six notes. Four have since been
acted on — the habitat threshold, the village beat trigger, and the two medals
now proven by plan variants — leaving two, both of which need authoring rather
than engineering. What follows is the finding and what was done about it.

### Levels could be won before a single month passed

| Mission | Goals all met | Time limit |
|---|---|---|
| habitat | **month 60**, after all 207 tiles (was: month 0, after 124) | 240 months |
| tuebingen | after 78 of 118 tiles, month 0 | 120 months |
| village | month 3 | 120 months |
| noise | month 18 | 96 months |
| quarter | month 27 | 180 months |
| budget | month 41 | 72 months |

On `habitat` and `tuebingen` **the end screen appeared while the player was
still building**, and everything the mission is nominally about had no bearing
on the outcome: the time limit and the seasonal cycle never came into play, and
neither did the maturation model.

**`habitat` is fixed.** Its biodiversity goal was 70, and the worked plan
starts at 71.8 — met before a month passed. Biodiversity then climbs by
maturation alone:

| month | 0 | 15 | 29 | 44 | 60 | 76 | 94 | 113 | plateau |
|---|---|---|---|---|---|---|---|---|---|
| biodiversity | 71.8 | 74 | 76 | 78 | **80** | 82 | 84 | 86 | 86.8 |

The goal is now **80**, which the worked plan reaches at **month 60** — a
quarter of the level's 240-month limit, and only by waiting. That single number
fixes three things at once: the level is no longer won mid-build, the
`recoveryMonths` and `biotopeStart` parameters the mission exists to teach now
decide it, and the `habitat_maturity` beat (below) finally fires.

80 rather than 84 or 86 because the ceiling is 86.8: a threshold nearer the
plateau leaves no headroom for a plan worse than the worked one, and would make
the `habitat_fast` medal (≤ 120 months) nearly impossible rather than merely
demanding.

**`tuebingen` needed a different lever**, because nothing in it matures:
biodiversity moves 38.6 → 39.8 over 120 months, climate and recreation are
flat. The two things that do move are population and the budget — and the
worked plan spends 29 090 of the level's 34 000 k€, leaving the town on 4 910
and recovering about 2 000 k€ a month.

So the level gained a fifth goal, `budgetKEur ≥ 50 000`, which the worked plan
reaches at **month 23 of 120**. It makes the level's own story — a town that
spends its reserves to undo its sealed surfaces — the thing you have to
survive. The threshold was checked against four variants of the plan before it
was committed:

| Variant | spent | reaches 50 000 k€ |
|---|---|---|
| worked plan | 29 090 | month 23 |
| parks replaced by forest | 11 840 | month 12 |
| half the plan | 11 350 | month 12 |
| no tram or cycle path | 21 100 | month 19 |

The recovery is a straight line at ~2 000 k€/month, so every variant lands well
inside the limit. `population` was the alternative and was rejected: the
ceiling is 22 281 against a start of 21 668, a window of 613 — about 3 % —
which is far too brittle for a goal threshold.

### Two beats were unreachable for a competent player; both are fixed

`habitat_maturity` fired `afterMonths: 36` against a level decided at month 0.
The goal change above fixed it, and its copy ("Give it time" / "Gib ihm Zeit")
was written for exactly this and had never been reachable.

`village_quiet_left` fired `afterMonths: 24` and the worked plan finishes
village in 3 months. Here the fix was the trigger, not the level: village is
the tutorial, and making the first mission take two years of clicking to
deliver one card would be worse than the problem. The beat says *"Look at what
is still meadow and forest. A village that reaches everything but keeps nothing
quiet has only solved half the task."* That is a thing to notice once the
village has taken shape, not after two years of waiting — so it now fires at
`afterTilesPlaced: 16`, half the level's tile budget, matching
`village_first_homes` at 4.

**Every beat in every mission now fires on the worked solution.** The lesson
generalises: a month-based trigger only works in a mission whose outcome takes
months, and two of the five were not.

### The habitat hint had nothing to suggest — fixed

`habitat` carries a `housing ≥ 50` goal and allows no housing tile: the goal is
there to stop the player bulldozing the village, which is good design. But the
tactical hint treated every unmet goal as something to build, walked its four
stages, and arrived with no tile to name — falling back to *"Explore the map
and try a different balance"*, which is true and useless.

There is now a stage for it. When none of a goal's candidate tiles is in the
level's palette, the hint ends on:

> **EN** Nothing you can build here raises {goal}. Protect what is already on
> the map.
> **DE** Hier lässt sich {goal} nicht dazubauen. Schütze, was schon da ist.

No schema change was needed: `guidanceCandidatesFor(goal)` against the level's
palette is the same test the audit already ran to find the problem. The audit
keeps reporting the situation as a note, so a new level of this shape is
noticed rather than silently inheriting the wording.

### The hint did not know about six of the sixteen tiles

Adding the budget goal to `tuebingen` immediately produced a second
preservation-goal note — for `budgetKEur`, whose candidates were `commercial`
and `industry`, neither of which tuebingen allows. But tuebingen *does* allow
`mixed_use` (45 jobs/ha) and `school` (25), both of which raise the budget.

`guidanceCandidatesFor` had never been updated for the six tiles T-502 added,
so the hint could not suggest them for any goal. It now can:

| Goal | Added |
|---|---|
| biodiversity | `wetland` — biotope value 22, the highest in the game |
| climate | `solar_field` — −266 t CO₂/ha/yr |
| housing, population | `mixed_use` — 120 residents/ha |
| economy, budget, jobs | `mixed_use`, `school` |
| shopping | `mixed_use` |
| recreation | `wetland` |
| commuting | `tram_stop`, `cycle_path` — they shift mode share through `transitAccess` and `cycleAccess`, which `_modeFactor` reads |

This was a real bug hiding behind a level that never exercised it, and it took
adding one goal to a level with a modern palette to surface it.

### A constraint medal only means something if the constraint costs something

Two medals — `habitat_no_water` and `noise_no_roads` — were reported as met by
neither random play nor the worked plan, which reads as *possibly impossible*
and was the opposite. `tool/level_plans.dart` now carries a **variant of each
plan that exists to earn one medal**, derived from the plan by filtering rather
than written out, so it cannot fall out of step with it. The audit replays them
and fails if a variant stops solving or stops earning its medal, which turns
"nobody tried" into a machine-checked claim.

What they proved is worth recording:

| Medal | Plan as written | Plan with the constraint |
|---|---|---|
| `habitat_no_water` | solves month 60, 87.1 biodiversity | solves month 60, 87.1 biodiversity |
| `noise_no_roads` | solves month 18 | solves month 21 |

The constrained solutions are as good as the originals. The two ponds in the
habitat plan and the side road in the noise plan **cost budget and earn
nothing**. A constraint medal is a reward for giving something up; when there
is nothing to give up, it is a reward for noticing. Either those levels want a
reason to build water and side roads that the indicators do not currently
capture, or the medals want retiring.

### tuebingen taught nothing — partly fixed

The newest and largest level shipped with goals and no `learning` block at all.
It now carries a **tier 1** block — concepts and features, no authored moments:

```json
"learning": {
  "tier": "explorer",
  "concepts": ["mixed_city", "tradeoffs", "resilience"],
  "features": ["causalView", "experiment", "debrief"]
}
```

That cost **no new copy**: all three concept ids already have Name, Cause,
Model and Law written in both languages, and it switches on the learning
notebook, the causal view, the experiment mode and the debrief.

Beats and a prediction are still to come, and they are deliberately absent
rather than stubbed. **Declaring beat ids before their copy exists would be
worse than having none**: the ICU `select` would render the generic wording,
which is precisely the failure this audit exists to catch. The test that used
to require beats of every mission now requires concepts instead, and says why.

## References

- `packages/stadtbau_sim/lib/src/level.dart` — `MissionLearning`, `MissionBeat`,
  `MissionChallenge`, `predictionChoicesFor`, `guidanceCandidatesFor`
- `packages/stadtbau_sim/tool/level_plans.dart` — the worked plans
- `app/lib/ui/learning_center.dart`, `app/lib/ui/goals_panel.dart` — where the
  copy is drawn
