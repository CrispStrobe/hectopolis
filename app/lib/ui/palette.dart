// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:stadtbau_sim/stadtbau_sim.dart';

import '../game/game_controller.dart';
import '../l10n/generated/app_localizations.dart';
import 'tile_style.dart';

/// Draggable tile cards, grouped by category. Tapping a card selects it as a
/// brush so touch users can place tiles by tapping cells.
class Palette extends StatelessWidget {
  const Palette({super.key, required this.controller, this.horizontal = false});

  final GameController controller;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final types = controller.allowedTypes;
        final cards = [
          for (var i = 0; i < types.length; i++)
            _TileCard(
              controller: controller,
              type: types[i],
              compact: horizontal,
              index: i,
            ),
        ];
        if (horizontal) {
          return SizedBox(
            height: 92,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: cards,
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(8),
          children: [
            Text(
              l10n.paletteTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                l10n.paletteHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            ...cards,
          ],
        );
      },
    );
  }
}

class _TileCard extends StatelessWidget {
  const _TileCard({
    required this.controller,
    required this.type,
    required this.compact,
    required this.index,
  });

  final GameController controller;
  final TileType type;
  final bool compact;

  /// Position in the allowed-tile order; the first ten are reachable with the
  /// keys 1–9 and 0 while the map has focus (task T-203).
  final int index;

  String? get _shortcut => index < 10 ? '${(index + 1) % 10}' : null;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = TileStyle.of(type);
    final params = controller.sim.params.tile(type);
    final remaining = controller.sim.tileBudget.remaining(type);
    final selected = controller.brush == type;
    final money = NumberFormat.decimalPattern(
      Localizations.localeOf(context).toString(),
    );
    final cost = l10n.kEur(money.format(params.buildCostKEur.value));

    final content = Container(
      width: compact ? 84 : null,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.35),
        border: Border.all(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: compact
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(style.icon, color: style.iconColor, size: 26),
                Text(
                  l10n.tileName(type.id),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                if (!controller.simpleMode)
                  Text(cost, style: Theme.of(context).textTheme.labelSmall),
              ],
            )
          : Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: style.color,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(style.icon, color: style.iconColor),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.tileName(type.id),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      Text(
                        controller.simpleMode
                            ? (remaining == null
                                  ? l10n.unlimited
                                  : l10n.remainingLabel(remaining))
                            : '${l10n.costLabel(cost)} · ${remaining == null ? l10n.unlimited : l10n.remainingLabel(remaining)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (_shortcut != null) _ShortcutBadge(digit: _shortcut!),
              ],
            ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 3),
      child: Tooltip(
        message: l10n.tileDescription(type.id),
        waitDuration: const Duration(milliseconds: 600),
        child: Draggable<TileType>(
          data: type,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          onDragStarted: () => controller.select(null),
          feedback: Transform.translate(
            offset: const Offset(-24, -24),
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: style.color,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: const [
                    BoxShadow(blurRadius: 6, color: Colors.black38),
                  ],
                ),
                child: Icon(style.icon, color: style.iconColor),
              ),
            ),
          ),
          child: InkWell(
            onTap: () => controller.setBrush(type),
            borderRadius: BorderRadius.circular(8),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// The 1–9/0 keyboard shortcut of a tile card.
class _ShortcutBadge extends StatelessWidget {
  const _ShortcutBadge({required this.digit});

  final String digit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(digit, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}
