// SPDX-License-Identifier: AGPL-3.0-or-later
// Audits the teaching content of every mission, in both languages, without a
// browser (task T-305).
//
//   dart run tool/learning_audit.dart [--paths N] [--seed S] [--quiet]
//
// Two halves, because the two ways this content breaks are different.
//
// **Copy coverage.** Every piece of mission text is an ICU `select` keyed by a
// stable id: `missionBeatTitle`, `challengeName`, `learningConceptCause` and a
// dozen more. ICU has no exhaustiveness check — an id with no branch renders
// the `other` branch and looks like working copy — and `tools/i18n_lint.dart`
// only checks that the same *keys* exist in both ARB files, not that the same
// *branches* do. So a German build can silently fall back where the English
// one does not. This half enumerates every id the level data and the model
// enums actually produce, and checks each one against the branches in both
// files.
//
// **Reachability.** A beat that never fires and a challenge nobody can meet
// are both dead content that no unit test notices. This half plays every level
// along many randomised paths plus its worked plan from `tool/level_plans.dart`.
//
// The two halves fail differently, so the output separates them. **Problems**
// are deterministic: a missing ICU branch, a level with no worked plan, a plan
// that no longer solves, a goal whose hint can name no tile, a medal the game
// can never award. **Notes** are statistical or a matter of design judgement:
// a beat nobody happened to reach, a challenge no sample met. A note asks for
// a human; only a problem fails the run, which is what lets `tools/check.sh`
// run this with a small `--paths`.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:stadtbau_sim/stadtbau_sim.dart';

import 'level_plans.dart';

void main(List<String> args) {
  final paths = _intArg(args, '--paths') ?? 60;
  final seed = _intArg(args, '--seed') ?? 20260918;
  final quiet = args.contains('--quiet');
  final root = _repoRoot();

  final problems = <String>[];
  final notes = <String>[];
  final en = _Arb.read(File('${root.path}/app/lib/l10n/app_en.arb'));
  final de = _Arb.read(File('${root.path}/app/lib/l10n/app_de.arb'));

  final levels = Level.builtIn();
  stdout.writeln('== copy coverage (${levels.length} missions, 2 languages)');
  problems.addAll(_auditCopy(levels, en, de, quiet: quiet));

  stdout.writeln('\n== reachability ($paths paths per mission, seed $seed)');
  problems.addAll(
    _auditPaths(levels, paths: paths, seed: seed, quiet: quiet, notes: notes),
  );

  if (notes.isNotEmpty) {
    stdout.writeln('\n== notes (design observations, not failures)');
    for (final note in notes) {
      stdout.writeln('   $note');
    }
  }
  stdout.writeln('');
  if (problems.isEmpty) {
    stdout.writeln(
      'learning audit: ok${notes.isEmpty ? '' : ' (${notes.length} note(s))'}',
    );
    return;
  }
  stdout.writeln('== problems');
  for (final problem in problems) {
    stdout.writeln('   $problem');
  }
  stdout.writeln('learning audit: ${problems.length} problem(s)');
  exitCode = 1;
}

// ---------------------------------------------------------------- copy

/// Every id the data and the enums produce, against the ICU branch that has to
/// exist for it. A missing branch is not an error at build time and not a
/// visible error at run time — it is the generic wording, quietly.
List<String> _auditCopy(
  List<Level> levels,
  _Arb en,
  _Arb de, {
  required bool quiet,
}) {
  final problems = <String>[];
  final required = <String, Set<String>>{};
  void need(String key, Iterable<String> ids) =>
      required.putIfAbsent(key, () => <String>{}).addAll(ids);

  final levelIds = [for (final level in levels) level.id];
  need('levelTitle', levelIds);
  need('levelDescription', levelIds);

  final indicatorIds = [for (final i in Indicator.values) i.name];
  need('indicatorName', indicatorIds);
  need('indicatorHint', indicatorIds);
  need('indicatorSimpleHint', indicatorIds);
  need('indicatorFormula', indicatorIds);
  need('simpleGoal', indicatorIds);

  final tileIds = [for (final t in TileType.values) t.id];
  need('tileName', tileIds);
  need('tileDescription', tileIds);
  need('categoryName', [for (final c in TileCategory.values) c.id]);
  need('learningModeName', [for (final t in MissionTier.values) t.name]);
  need('learningModeDescription', [for (final t in MissionTier.values) t.name]);

  final metrics = <String>{};
  for (final level in levels) {
    for (final goal in level.goals) {
      final metric = goal.metric;
      if (metric != null) metrics.add(metric);
    }
  }
  need('goalMetricName', metrics);
  need('goalMetric', metrics);

  for (final level in levels) {
    final learning = level.learning;
    if (learning == null) continue;
    need('learningConceptName', learning.concepts);
    need('learningConceptCause', learning.concepts);
    need('learningConceptModel', learning.concepts);
    need('learningConceptLaw', learning.concepts);
    need('challengeName', learning.challengeIds);
    need('missionBeatTitle', [for (final b in learning.beats) b.id]);
    need('missionBeatBody', [for (final b in learning.beats) b.id]);
    final prediction = learning.predictionId;
    if (prediction != null) {
      need('missionPredictionPrompt', [prediction]);
      need('missionPredictionChoice', predictionChoicesFor(prediction));
      if (!hasPredictionChoices(prediction)) {
        problems.add(
          'prediction "$prediction" (${level.id}) has no answers of its own; '
          'predictionChoicesFor falls back to the generic three',
        );
      }
    }
  }

  var checked = 0;
  for (final entry in required.entries) {
    final key = entry.key;
    final enBranches = en.branches(key);
    final deBranches = de.branches(key);
    if (enBranches == null || deBranches == null) {
      problems.add(
        'key "$key" is missing or not a select in '
        '${enBranches == null ? 'en' : ''}${enBranches == null && deBranches == null ? ' and ' : ''}'
        '${deBranches == null ? 'de' : ''}',
      );
      continue;
    }
    for (final id in entry.value) {
      checked++;
      final missing = <String>[
        if (!enBranches.contains(id)) 'en',
        if (!deBranches.contains(id)) 'de',
      ];
      if (missing.isNotEmpty) {
        problems.add(
          '$key has no branch for "$id" in ${missing.join(' and ')} — '
          'falls back to the generic wording',
        );
      }
    }
    // A select can carry different branches in the two files even when the
    // key exists in both, which is exactly what the i18n lint cannot see.
    final onlyEn = enBranches.difference(deBranches)..remove('other');
    final onlyDe = deBranches.difference(enBranches)..remove('other');
    if (onlyEn.isNotEmpty) {
      problems.add('$key: branches in en but not de: ${_list(onlyEn)}');
    }
    if (onlyDe.isNotEmpty) {
      problems.add('$key: branches in de but not en: ${_list(onlyDe)}');
    }
  }
  if (!quiet) {
    stdout.writeln('   $checked ids across ${required.length} localized keys');
  }
  return problems;
}

// -------------------------------------------------------- reachability

List<String> _auditPaths(
  List<Level> levels, {
  required int paths,
  required int seed,
  required bool quiet,
  required List<String> notes,
}) {
  final problems = <String>[];
  for (final level in levels) {
    final learning = level.learning;
    final beatsSeen = <String, int>{};
    final challengesMet = <String, int>{};
    final awardableFromRandom = <String>{};
    final random = Random(seed + level.id.hashCode);
    var solved = 0;
    var guidanceWithoutTile = 0;

    for (var run = 0; run < paths; run++) {
      final result = _playRandomPath(level, random);
      if (result.solved) solved++;
      guidanceWithoutTile += result.guidanceWithoutTile;
      for (final id in result.beats) {
        beatsSeen[id] = (beatsSeen[id] ?? 0) + 1;
      }
      for (final id in result.challenges) {
        challengesMet[id] = (challengesMet[id] ?? 0) + 1;
      }
      awardableFromRandom.addAll(result.challengesAtEnd);
    }

    // The worked solution, which is what a competent player does. Random play
    // is a fuzzer: it finds triggers a plan happens to miss, but it cannot
    // tell a hard challenge from an impossible one.
    final plan = planFor(level.id);
    final planned = plan == null ? null : _playPlan(level, plan);
    final awardable = <String>{
      ...?planned?.challengesAtEnd,
      ...awardableFromRandom,
    };

    if (!quiet) {
      final planLength = plan?.length ?? 0;
      final planNote = planned == null
          ? 'no plan'
          : 'plan ${planned.solved ? 'solves in ${planned.months}/${level.turnLimitMonths} mo '
                        'after ${planned.placementsBeforeEnd}/$planLength tiles' : 'FAILS'}, '
                'beats ${planned.beats.length}, '
                'medals ${planned.challengesAtEnd.length}';
      stdout.writeln(
        '   ${level.id.padRight(10)} random $solved/$paths solved   '
        'beats ${beatsSeen.length}/${learning?.beats.length ?? 0}   '
        'challenges ${challengesMet.length}/${learning?.challenges.length ?? 0}   '
        '$planNote'
        '${guidanceWithoutTile > 0 ? '   hints with no tile to name: $guidanceWithoutTile' : ''}',
      );
    }
    if (plan == null) {
      problems.add(
        '${level.id}: no worked plan in tool/level_plans.dart, so nothing '
        'proves the level or its teaching content is reachable',
      );
    } else if (!planned!.solved) {
      problems.add('${level.id}: the worked plan no longer solves the level');
    }
    if (learning == null) {
      if (level.goals.isNotEmpty) {
        notes.add(
          '${level.id}: ships with goals but no learning block — no concepts, '
          'no prediction, no beats, no challenges',
        );
      }
      continue;
    }
    for (final beat in learning.beats) {
      final byRandom = beatsSeen.containsKey(beat.id);
      final byPlan = planned?.beats.contains(beat.id) ?? false;
      if (!byRandom && !byPlan) {
        notes.add(
          '${level.id}: beat "${beat.id}" fired neither in $paths random '
          'paths nor on the worked solution — its trigger looks unreachable '
          '(raise --paths before believing it)',
        );
      } else if (!byPlan && planned != null && planned.solved) {
        notes.add(
          '${level.id}: beat "${beat.id}" does not fire on the worked '
          'solution, which finishes in ${planned.months} months — a player '
          'who plays well never reaches this teaching moment',
        );
      }
    }
    for (final challenge in learning.challenges) {
      final byRandom = challengesMet.containsKey(challenge.id);
      final byPlan = planned?.challenges.contains(challenge.id) ?? false;
      if (!byRandom && !byPlan) {
        notes.add(
          '${level.id}: challenge "${challenge.id}" was met neither in $paths '
          'random paths nor by the worked solution — it may be impossible, or '
          'the sample may be too small (raise --paths)',
        );
      } else if (!awardable.contains(challenge.id)) {
        // The game reads the challenges once, at the moment the goals are all
        // met, and banks the medals then. A challenge that is only satisfied
        // before or after that instant can never be awarded.
        problems.add(
          '${level.id}: challenge "${challenge.id}" is satisfied at some point '
          'but never at the moment the level ends, which is the only moment '
          'the game awards it',
        );
      }
    }
    if (planned != null && planned.decidedAtMonth == 0) {
      final placedOf = plan == null
          ? ''
          : ' after ${planned.placementsBeforeEnd} of its ${plan.length} tiles';
      notes.add(
        '${level.id}: the worked plan meets every goal$placedOf, before a '
        'single month passes — the ${level.turnLimitMonths}-month limit, the '
        'seasonal cycle and the maturation model never bear on the outcome, '
        'and the end screen appears while the player is still building',
      );
    }
    // A goal whose guidance candidates the level forbids leaves the hint with
    // nothing to name.
    for (final goal in level.goals) {
      final candidates = guidanceCandidatesFor(goal);
      final label = goal.indicator?.name ?? goal.metric ?? '?';
      if (candidates.isEmpty) {
        problems.add(
          '${level.id}: goal "$label" has no guidance candidates at all',
        );
        continue;
      }
      if (!candidates.any(level.tiles.containsKey)) {
        notes.add(
          '${level.id}: goal "$label" points at '
          '${_list(candidates.map((t) => t.id))} and the level allows none of '
          'them, so the hint reaches its last stage with no tile to name '
          '(it falls back to "explore", which is true but not actionable)',
        );
      }
    }
  }
  return problems;
}

class _PathResult {
  _PathResult({
    required this.solved,
    required this.beats,
    required this.challenges,
    required this.guidanceTicks,
    required this.guidanceWithoutTile,
    this.months = 0,
    this.challengesAtEnd = const {},
    this.decidedAtMonth,
    this.placementsBeforeEnd,
  });

  final bool solved;
  final int months;
  final Set<String> beats;

  /// Challenges met at any point during the run.
  final Set<String> challenges;

  /// Challenges met at the moment the goals were all met — the only moment the
  /// game looks, because that is when it banks the stars and the medals.
  final Set<String> challengesAtEnd;

  /// Month at which every goal was first met, or null if they never were.
  final int? decidedAtMonth;

  /// Tiles of the plan that had been placed when the level ended. Fewer than
  /// the plan holds means the end screen appeared mid-build.
  final int? placementsBeforeEnd;
  final int guidanceTicks;
  final int guidanceWithoutTile;
}

/// One player who builds at random within the level's own rules, and whose
/// every month is checked for beats, challenges and a usable hint.
_PathResult _playRandomPath(Level level, Random random) {
  final sim = level.start();
  final beats = <String>{};
  final challenges = <String>{};
  final learning = level.learning;
  final palette = level.tiles.keys.toList();
  final months = level.turnLimitMonths ?? 120;
  var guidanceTicks = 0;
  var guidanceWithoutTile = 0;

  // Build in bursts, so the run passes through states with few tiles and
  // states with many — a beat keyed to "after three tiles" must be seen by a
  // player who places three, not only by one who places thirty.
  var placements = 0;
  final budgetPerBurst = 1 + random.nextInt(4);
  for (var month = 0; month < months; month++) {
    for (var k = 0; k < budgetPerBurst; k++) {
      if (palette.isEmpty) break;
      final tile = palette[random.nextInt(palette.length)];
      final x = random.nextInt(sim.state.width);
      final y = random.nextInt(sim.state.height);
      if (sim.apply(PlaceTile(x, y, tile)).ok) placements++;
    }
    sim.apply(const AdvanceTick());
    final progress = level.evaluate(sim.indicators);
    if (learning != null) {
      for (final beat in learning.beats) {
        if (beat.isReached(level, sim, progress)) beats.add(beat.id);
      }
      for (final challenge in learning.challenges) {
        if (challenge.met(level, sim, progress)) challenges.add(challenge.id);
      }
    }
    final guidance = _guidanceFor(level, sim, progress);
    if (guidance != null) {
      guidanceTicks++;
      if (guidance.tile == null) guidanceWithoutTile++;
    }
    if (progress.allMet && placements > 0) {
      return _PathResult(
        solved: true,
        months: month + 1,
        decidedAtMonth: month + 1,
        beats: beats,
        challenges: challenges,
        challengesAtEnd: {
          for (final challenge in learning?.challenges ?? const <MissionChallenge>[])
            if (challenge.met(level, sim, progress)) challenge.id,
        },
        guidanceTicks: guidanceTicks,
        guidanceWithoutTile: guidanceWithoutTile,
      );
    }
  }
  return _PathResult(
    solved: false,
    beats: beats,
    challenges: challenges,
    guidanceTicks: guidanceTicks,
    guidanceWithoutTile: guidanceWithoutTile,
  );
}

/// Replay a worked plan and watch the same things the random paths watch.
_PathResult _playPlan(Level level, List<Move> plan) {
  final sim = level.start();
  final learning = level.learning;
  final beats = <String>{};
  final challenges = <String>{};
  var guidanceWithoutTile = 0;
  var guidanceTicks = 0;
  var placed = 0;

  void observe() {
    final progress = level.evaluate(sim.indicators);
    if (learning != null) {
      for (final beat in learning.beats) {
        if (beat.isReached(level, sim, progress)) beats.add(beat.id);
      }
      for (final challenge in learning.challenges) {
        if (challenge.met(level, sim, progress)) challenges.add(challenge.id);
      }
    }
    final guidance = _guidanceFor(level, sim, progress);
    if (guidance != null) {
      guidanceTicks++;
      if (guidance.tile == null) guidanceWithoutTile++;
    }
  }

  // The game ends at the *first* moment every goal is met, and that is the
  // only moment it banks the stars and the medals: `_recompute` runs after
  // every placement, so the end screen can appear while the player is still
  // building. The harness has to stop where the game stops, or it credits
  // medals the player would never be given.
  _PathResult? endedAt(int month) {
    final progress = level.evaluate(sim.indicators);
    if (!progress.allMet) return null;
    return _PathResult(
      solved: true,
      months: month,
      decidedAtMonth: month,
      placementsBeforeEnd: placed,
      beats: beats,
      challenges: challenges,
      challengesAtEnd: {
        for (final challenge
            in learning?.challenges ?? const <MissionChallenge>[])
          if (challenge.met(level, sim, progress)) challenge.id,
      },
      guidanceTicks: guidanceTicks,
      guidanceWithoutTile: guidanceWithoutTile,
    );
  }

  // Beats are checked along the way too: one keyed to "after three tiles" has
  // to be seen by the player who has placed three, not only by one who
  // finished.
  for (final (x, y, tile) in plan) {
    sim.apply(PlaceTile(x, y, tile));
    placed++;
    observe();
    final end = endedAt(0);
    if (end != null) return end;
  }
  final months = level.turnLimitMonths ?? 120;
  for (var month = 0; month < months; month++) {
    sim.apply(const AdvanceTick());
    observe();
    final end = endedAt(month + 1);
    if (end != null) return end;
  }
  return _PathResult(
    solved: false,
    months: months,
    beats: beats,
    challenges: challenges,
    guidanceTicks: guidanceTicks,
    guidanceWithoutTile: guidanceWithoutTile,
  );
}

class _Guidance {
  _Guidance(this.tile);
  final TileType? tile;
}

/// The same choice the goals panel makes: the goal furthest from its target,
/// and a tile the level still allows for it.
_Guidance? _guidanceFor(Level level, Simulation sim, LevelProgress progress) {
  var weakest = -1;
  var weakestRatio = double.infinity;
  for (var i = 0; i < level.goals.length; i++) {
    if (progress.goalsMet[i]) continue;
    final goal = level.goals[i];
    final ratio = goal.current(sim.indicators) / goal.min;
    if (ratio < weakestRatio) {
      weakest = i;
      weakestRatio = ratio;
    }
  }
  if (weakest < 0) return null;
  for (final tile in guidanceCandidatesFor(level.goals[weakest])) {
    final remaining = sim.tileBudget.remaining(tile);
    if (sim.tileBudget.allowed(tile) && (remaining == null || remaining > 0)) {
      return _Guidance(tile);
    }
  }
  return _Guidance(null);
}

// ------------------------------------------------------------- helpers

/// An ARB file, reduced to the branch names of each ICU `select`.
class _Arb {
  _Arb(this._selects);

  final Map<String, Set<String>> _selects;

  Set<String>? branches(String key) => _selects[key];

  static _Arb read(File file) {
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final selects = <String, Set<String>>{};
    for (final entry in json.entries) {
      if (entry.key.startsWith('@')) continue;
      final value = entry.value;
      if (value is! String) continue;
      final branches = _selectBranches(value);
      if (branches != null) selects[entry.key] = branches;
    }
    return _Arb(selects);
  }

  /// Branch names of `{arg, select, a{…} b{…} other{…}}`, or null if the
  /// message is not a select. Brace-counting rather than a regex, because a
  /// branch body may itself contain braces.
  static Set<String>? _selectBranches(String message) {
    final start = RegExp(r'\{\s*\w+\s*,\s*select\s*,').firstMatch(message);
    if (start == null) return null;
    final branches = <String>{};
    var i = start.end;
    while (i < message.length) {
      while (i < message.length && message[i].trim().isEmpty) {
        i++;
      }
      if (i >= message.length || message[i] == '}') break;
      final nameStart = i;
      while (i < message.length && message[i] != '{') {
        i++;
      }
      if (i >= message.length) break;
      final name = message.substring(nameStart, i).trim();
      var depth = 0;
      do {
        if (message[i] == '{') depth++;
        if (message[i] == '}') depth--;
        i++;
      } while (i < message.length && depth > 0);
      if (name.isNotEmpty) branches.add(name);
    }
    return branches;
  }
}

String _list(Iterable<String> values) => (values.toList()..sort()).join(', ');

int? _intArg(List<String> args, String name) {
  final i = args.indexOf(name);
  if (i < 0 || i + 1 >= args.length) return null;
  return int.tryParse(args[i + 1]);
}

Directory _repoRoot() {
  var dir = Directory.current;
  for (var up = 0; up < 6; up++) {
    if (File('${dir.path}/PLAN.md').existsSync()) return dir;
    dir = dir.parent;
  }
  throw StateError('run this from inside the repository');
}
