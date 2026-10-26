// SPDX-License-Identifier: AGPL-3.0-or-later
part of '../map_view.dart';

class _PlacementModeChip extends StatelessWidget {
  const _PlacementModeChip({
    required this.tile,
    required this.onCancel,
    required this.level,
  });

  final TileType tile;
  final VoidCallback onCancel;

  /// For the tile's name: a level may call this type something else.
  final Level? level;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = TileStyle.of(tile);
    return InputChip(
      elevation: 3,
      avatar: Icon(style.icon, size: 18, color: style.iconColor),
      label: Text(l10n.placementMode(tileDisplayName(l10n, level, tile))),
      deleteIcon: const Icon(Icons.close, size: 18),
      deleteButtonTooltipMessage: l10n.actionCancelPlacement,
      onDeleted: onCancel,
    );
  }
}

class _PlacementPreviewCard extends StatelessWidget {
  const _PlacementPreviewCard({
    required this.preview,
    required this.simpleMode,
    required this.level,
  });

  final PlacementPreview preview;
  final bool simpleMode;
  final Level? level;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final number = NumberFormat.decimalPatternDigits(
      locale: Localizations.localeOf(context).toString(),
      decimalDigits: 0,
    );
    final changes =
        preview.indicatorDeltas.entries
            .where((entry) => entry.value.isFinite && entry.value.abs() >= 0.05)
            .toList()
          ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    final error = switch (preview.error) {
      CommandError.outOfBounds => l10n.errorOutOfBounds,
      CommandError.sameTile => null,
      CommandError.insufficientBudget => l10n.errorInsufficientBudget,
      CommandError.tileNotAllowed => l10n.errorTileNotAllowed,
      CommandError.tileExhausted => l10n.errorTileExhausted,
      null => null,
    };
    final scheme = theme.colorScheme;
    return IgnorePointer(
      child: Card(
        elevation: 4,
        color: scheme.surface.withValues(alpha: 0.94),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 230),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      TileStyle.of(preview.tile).icon,
                      size: 18,
                      color: TileStyle.of(preview.tile).iconColor,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        l10n.placementPreviewTitle(
                          tileDisplayName(l10n, level, preview.tile),
                        ),
                      ),
                    ),
                  ],
                ),
                if (!simpleMode)
                  if (preview.costKEur case final cost?)
                    Text(
                      l10n.placementPreviewCost(l10n.kEur(number.format(cost))),
                      style: theme.textTheme.bodySmall,
                    ),
                if (error != null)
                  Text(
                    error,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                    ),
                  )
                else if (simpleMode)
                  _friendlyImpactLine(l10n, changes, theme.textTheme.bodySmall)
                else if (changes.isEmpty)
                  Text(
                    l10n.placementPreviewNoScoreChange,
                    style: theme.textTheme.bodySmall,
                  )
                else
                  for (final change in changes.take(3))
                    Text(
                      '${l10n.indicatorName(change.key.name)} ${change.value >= 0 ? '+' : ''}${change.value.toStringAsFixed(1)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: change.value >= 0
                            ? const Color(0xFF2E7D32)
                            : scheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                if (preview.isValid && !simpleMode)
                  Text(
                    l10n.placementPreviewAffected(
                      preview.affectedCells.length,
                      l10n.overlayName(preview.affectedOverlay.name),
                    ),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Simple mode's verdict on a placement: an icon and a sentence.
///
/// The sentences used to carry an emoji of their own. They no longer do:
/// an emoji is not in Roboto, so each one made CanvasKit fetch a colour-emoji
/// font from Google on the web (docs/web-payload.md). The icon font is already
/// bundled, and an icon can take the theme colour.
(IconData, String) _friendlyImpact(
  AppLocalizations l10n,
  List<MapEntry<Indicator, double>> changes,
) {
  const steady = (Icons.sentiment_neutral, null);
  if (changes.isEmpty) return (steady.$1, l10n.impactSimpleSteady);
  final total = changes.fold<double>(0, (sum, entry) => sum + entry.value);
  final positive = changes.any((entry) => entry.value > 0.15);
  final negative = changes.any((entry) => entry.value < -0.15);
  if (positive && negative) {
    return (Icons.compare_arrows, l10n.impactSimpleMixed);
  }
  if (total > 0.15) {
    return (Icons.sentiment_satisfied, l10n.impactSimpleBetter);
  }
  if (total < -0.15) {
    return (Icons.sentiment_dissatisfied, l10n.impactSimpleWorse);
  }
  return (steady.$1, l10n.impactSimpleSteady);
}

/// One line of simple-mode feedback, icon first.
Widget _friendlyImpactLine(
  AppLocalizations l10n,
  List<MapEntry<Indicator, double>> changes,
  TextStyle? style,
) {
  final (icon, text) = _friendlyImpact(l10n, changes);
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18),
      const SizedBox(width: 6),
      Expanded(child: Text(text, style: style)),
    ],
  );
}

class _BuildImpactCard extends StatelessWidget {
  const _BuildImpactCard({
    required this.impact,
    required this.simpleMode,
    required this.onClose,
    required this.level,
  });

  final BuildImpact impact;
  final bool simpleMode;
  final VoidCallback onClose;
  final Level? level;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final changes =
        impact.indicatorDeltas.entries
            .where((entry) => entry.value.isFinite && entry.value.abs() >= 0.05)
            .toList()
          ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    return Card(
      elevation: 5,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    impact.removed ? Icons.delete_outline : Icons.check_circle,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      impact.removed
                          ? l10n.impactRemoved(
                              tileDisplayName(l10n, level, impact.tile),
                            )
                          : l10n.impactBuilt(
                              tileDisplayName(l10n, level, impact.tile),
                            ),
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: l10n.actionClose,
                    icon: const Icon(Icons.close, size: 17),
                    onPressed: onClose,
                  ),
                ],
              ),
              if (simpleMode)
                _friendlyImpactLine(l10n, changes, theme.textTheme.bodyMedium)
              else if (changes.isEmpty)
                Text(
                  l10n.placementPreviewNoScoreChange,
                  style: theme.textTheme.bodySmall,
                )
              else
                for (final change in changes.take(3))
                  Text(
                    '${l10n.indicatorName(change.key.name)} ${change.value >= 0 ? '+' : ''}${change.value.toStringAsFixed(1)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: change.value >= 0
                          ? const Color(0xFF2E7D32)
                          : theme.colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              if (!simpleMode)
                Text(
                  l10n.placementPreviewAffected(
                    impact.affectedCells.length,
                    l10n.overlayName(impact.affectedOverlay.name),
                  ),
                  style: theme.textTheme.labelSmall,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
