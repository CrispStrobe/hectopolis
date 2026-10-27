// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:stadtbau_sim/stadtbau_sim.dart';

import 'game_types.dart';
import 'overlay_math.dart';

/// How many of the nearest marked sources are weighed. Enough that a strong
/// source a few cells away (an industrial estate behind a row of houses) is
/// among them; few enough that weighing them stays a fraction of a second on
/// the largest map.
const sourceCandidateCount = 12;

/// How many source lines the map draws.
const shownSourceCount = 6;

/// [sim] as it would be without the tile at [cell]: the cell goes back to
/// meadow and loses its residents. Not a command, because a command charges
/// demolition and can be refused; this is a counterfactual, not a move.
Simulation withoutTile(Simulation sim, int cell) {
  final after = sim.copy();
  after.state.tiles[cell] = TileType.terrain;
  after.state.population[cell] = 0;
  after.state.tileAge[cell] = 0;
  after.recompute();
  return after;
}

/// The marked sources around [receiver], ordered by how much each one moves
/// the [overlay] value there.
///
/// For the overlays [Simulation.sources] cannot take apart: traffic and
/// attractiveness. Removing one tile is a fair test for those because neither
/// is capped in practice; on a capped field (job access at 1.0) no single
/// removal would register, which is why the others are traced instead.
///
/// Weighing a source means recomputing the model without it, so the work is
/// spread over event-loop turns, one candidate each: the map keeps drawing,
/// shows the nearest sources straight away, and swaps in the ranked order
/// through [onDone] once every candidate is weighed.
class SourceRanking {
  SourceRanking({
    required this.sim,
    required this.overlay,
    required this.receiver,
    required this.candidates,
    required this.revision,
  }) : _effect = List<double?>.filled(candidates.length, null);

  final Simulation sim;
  final MapOverlay overlay;
  final int receiver;

  /// Marked source cells, nearest first.
  final List<int> candidates;

  /// The visual revision of the simulation this ranking describes.
  final int revision;

  final List<double?> _effect;
  Timer? _timer;
  var _next = 0;

  bool get isComplete => _next >= candidates.length;

  bool matches(MapOverlay overlay, int receiver, int revision) =>
      overlay == this.overlay &&
      receiver == this.receiver &&
      revision == this.revision;

  /// The cells to draw lines from: by effect once weighed, nearest first
  /// until then. Sources that do not move the value at all come last, so a
  /// saturated reading (every shop in reach, and one more changes nothing)
  /// still shows where it comes from.
  List<int> get shown {
    if (!isComplete) {
      return candidates.take(shownSourceCount).toList(growable: false);
    }
    final order = List<int>.generate(candidates.length, (i) => i)
      ..sort((a, b) {
        final byEffect = _effect[b]!.compareTo(_effect[a]!);
        return byEffect != 0 ? byEffect : a.compareTo(b);
      });
    return [for (final i in order.take(shownSourceCount)) candidates[i]];
  }

  /// Weighs one more candidate; returns false once all are weighed.
  bool step() {
    if (isComplete) return false;
    final i = _next++;
    _effect[i] = fieldDifference(
      overlay,
      sim,
      withoutTile(sim, candidates[i]),
      receiver,
    );
    return !isComplete;
  }

  /// Weighs every candidate, one per event-loop turn, then calls [onDone].
  void start(void Function() onDone) {
    void run() {
      if (step()) {
        _timer = Timer(Duration.zero, run);
      } else {
        _timer = null;
        onDone();
      }
    }

    _timer = Timer(Duration.zero, run);
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
