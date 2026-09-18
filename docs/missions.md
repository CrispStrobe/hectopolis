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

**`tuebingen` is not fixed**, because it is not the same problem. Biodiversity
there moves 39 → 41 over 240 months against a goal of 38: the level is decided
entirely by what the player removes, and it happens instantly. Making time
matter there needs a different lever than a threshold, and it wants the
project's judgement.

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

### The habitat hint has nothing to suggest

`habitat` carries a `housing ≥ 50` goal and allows no housing tile — the goal
is there to stop the player bulldozing the village, which is a good design. But
the tactical hint treats every unmet goal as something to build, walks its four
stages, and arrives with no tile to name (it falls back to "explore", which is
true but not actionable). In 12 paths that happened 976 times. Either the hint
wants a "protect what is there" stage, or preservation goals want marking as
such in the level schema.

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

### tuebingen teaches nothing

The newest and largest level ships with goals and no `learning` block at all:
no concepts, no prediction, no beats, no challenges. Every other mission has
them. This is authoring work, and the copy wants the project's voice.

## References

- `packages/stadtbau_sim/lib/src/level.dart` — `MissionLearning`, `MissionBeat`,
  `MissionChallenge`, `predictionChoicesFor`, `guidanceCandidatesFor`
- `packages/stadtbau_sim/tool/level_plans.dart` — the worked plans
- `app/lib/ui/learning_center.dart`, `app/lib/ui/goals_panel.dart` — where the
  copy is drawn
