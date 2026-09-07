// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:stadtbau_sim/stadtbau_sim.dart';

import '../game/game_controller.dart';
import '../l10n/generated/app_localizations.dart';
import 'tile_style.dart';

/// Per-cell values of every field for the selected cell.
class TileInspector extends StatelessWidget {
  const TileInspector({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final cell = controller.selectedCell;
        if (cell == null) {
          return Padding(
            padding: const EdgeInsets.all(8),
            child: Text(l10n.inspectorEmpty, style: theme.textTheme.bodySmall),
          );
        }
        final sim = controller.sim;
        final f = sim.fields;
        final x = cell % sim.state.width;
        final y = cell ~/ sim.state.width;
        final type = sim.state.tiles[cell];
        final style = TileStyle.of(type);
        if (controller.simpleMode) {
          String face(double value) {
            if (value >= 0.75) return '😄';
            if (value >= 0.5) return '🙂';
            if (value >= 0.3) return '😐';
            return '🙁';
          }

          final conditions = <(String, double)>[
            (l10n.fieldNoise, ((65 - f.noiseDb[cell]) / 30).clamp(0, 1)),
            (l10n.fieldAir, (1 - f.airIndex[cell] / 100).clamp(0, 1)),
            (l10n.fieldGreen, f.greenAccess[cell]),
            (l10n.fieldAttractiveness, f.attractiveness[cell]),
          ];
          return ListView(
            padding: const EdgeInsets.all(8),
            children: [
              Row(
                children: [
                  Icon(style.icon, color: style.iconColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.tileName(type.id),
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.actionClear,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => controller.clear(x, y),
                  ),
                ],
              ),
              Text(
                l10n.tileDescription(type.id),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              for (final (label, value) in conditions)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(label),
                  trailing: Text(face(value)),
                ),
            ],
          );
        }
        final locale = Localizations.localeOf(context).toString();
        final n0 = NumberFormat.decimalPatternDigits(
          locale: locale,
          decimalDigits: 0,
        );
        final n1 = NumberFormat.decimalPatternDigits(
          locale: locale,
          decimalDigits: 1,
        );
        final n2 = NumberFormat.decimalPatternDigits(
          locale: locale,
          decimalDigits: 2,
        );

        final rows = <(String, String)>[
          (l10n.fieldNoise, l10n.dbValue(n0.format(f.noiseDb[cell]))),
          (l10n.fieldAir, n0.format(f.airIndex[cell])),
          (l10n.fieldHeat, l10n.degreesValue(n1.format(f.heatDeltaC[cell]))),
          (l10n.fieldGreen, n2.format(f.greenAccess[cell])),
          (l10n.fieldRetail, n2.format(f.retailAccess[cell])),
          (l10n.fieldJobs, n2.format(f.jobAccess[cell])),
          (l10n.fieldHabitat, n2.format(f.habitatQuality[cell])),
          (l10n.fieldTraffic, l10n.vehiclesValue(n0.format(f.traffic[cell]))),
          (l10n.fieldAttractiveness, n2.format(f.attractiveness[cell])),
          (l10n.fieldResidents, n0.format(sim.state.population[cell])),
          (l10n.fieldCommute, l10n.kmValue(n1.format(f.meanCommuteKm[cell]))),
          (
            l10n.fieldCarShare,
            l10n.percentValue(n0.format(f.carShare[cell] * 100)),
          ),
          (l10n.fieldConnected, f.connected[cell] == 1 ? l10n.yes : l10n.no),
          (l10n.fieldAge, l10n.months(sim.state.tileAge[cell])),
        ];

        return ListView(
          padding: const EdgeInsets.all(8),
          children: [
            Row(
              children: [
                Icon(style.icon, color: style.iconColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${l10n.inspectorTitle(x, y)} · ${l10n.tileName(type.id)}',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: l10n.actionClear,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => controller.clear(x, y),
                ),
              ],
            ),
            Text(
              l10n.tileDescription(type.id),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(label, style: theme.textTheme.bodySmall),
                    ),
                    Text(value, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            _Breakdown(
              title: l10n.breakdownNoise,
              rows: sim.explainNoise(x, y),
              format: (c) => l10n.dbValue(n0.format(c.value)),
              cellSizeM: sim.params.cellSizeM,
            ),
            _Breakdown(
              title: l10n.breakdownAir,
              rows: sim.explainAir(x, y),
              format: (c) => n2.format(c.value),
              cellSizeM: sim.params.cellSizeM,
            ),
          ],
        );
      },
    );
  }
}

/// Which tile types cause a field value at the selected cell (task T-206).
class _Breakdown extends StatelessWidget {
  const _Breakdown({
    required this.title,
    required this.rows,
    required this.format,
    required this.cellSizeM,
  });

  final String title;
  final List<Contribution> rows;
  final String Function(Contribution) format;
  final double cellSizeM;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    final n0 = NumberFormat.decimalPatternDigits(
      locale: locale,
      decimalDigits: 0,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.labelLarge),
        if (rows.isEmpty)
          Text(l10n.breakdownNone, style: theme.textTheme.bodySmall),
        for (final c in rows.take(5))
          Row(
            children: [
              Icon(
                TileStyle.of(c.type).icon,
                size: 14,
                color: TileStyle.of(c.type).iconColor,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  l10n.breakdownRow(
                    l10n.tileName(c.type.id),
                    c.count,
                    n0.format(c.nearestTiles * cellSizeM),
                  ),
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(format(c), style: theme.textTheme.bodySmall),
            ],
          ),
        const SizedBox(height: 4),
      ],
    );
  }
}
