// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:stadtbau_sim/stadtbau_sim.dart';

import '../game/game_controller.dart';
import '../l10n/generated/app_localizations.dart';
import 'tile_naming.dart';
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
          // A horizontal list states its own height, because it cannot take
          // one from its children -- and a stated height clips them as soon as
          // the player raises the system font size. WCAG 1.4.4 asks for 200 %
          // text without loss of content, and at 100 % the literal 92 was
          // already 4 px short of the icon plus name plus cost.
          //
          // Scaling the literal by the text scaler was tried first and is not
          // enough: the content does not grow linearly (a 26 px icon does not
          // scale at all, a line box grows faster than its font size), so one
          // factor was both too generous here and 22 px short in the indicator
          // strip. The height therefore comes from the content, with the old
          // literal kept as a floor so the default layout is unchanged.
          // IntrinsicHeight, so every card is still as tall as the tallest.
          return ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 92),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: IntrinsicHeight(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: cards,
                ),
              ),
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
    final remaining = controller.remaining(type);
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
                  tileDisplayName(l10n, controller.level, type),
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
                        tileDisplayName(l10n, controller.level, type),
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

    // A card is an icon, a name, a cost and a badge. One label carries all of
    // it plus the selected state, which the coloured border shows and nothing
    // else conveys.
    final spoken = selected
        ? l10n.a11yTileSelected(tileDisplayName(l10n, controller.level, type))
        : l10n.a11yTileCard(
            tileDisplayName(l10n, controller.level, type),
            cost,
            remaining == null
                ? l10n.a11yRemainingUnlimited
                : l10n.a11yRemainingCount(remaining),
          );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 3),
      child: Semantics(
        label: spoken,
        hint: tileDisplayDescription(l10n, controller.level, type),
        button: true,
        selected: selected,
        container: true,
        excludeSemantics: true,
        onTap: () => controller.setBrush(type),
        child: Tooltip(
          message: tileDisplayDescription(l10n, controller.level, type),
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
              // Selection is the coloured border; focus is this wash. They are
              // different states — the card Tab lands on is not yet the brush.
              focusColor: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.22),
              child: content,
            ),
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
