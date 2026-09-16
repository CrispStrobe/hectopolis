// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:stadtbau_sim/stadtbau_sim.dart';

import '../game/game_controller.dart';
import '../l10n/generated/app_localizations.dart';

/// The causal loop view (T-504): the feedback loops of the model, with the one
/// currently doing the most to the town at the top.
///
/// Drawn as chains rather than a node graph. Five loops sharing nodes make a
/// tangle at phone width, and the thing worth reading is the order of the
/// steps — people arrive, drive, foul the air, stop arriving — which a chain
/// says plainly and a diagram usually hides.
Future<void> showCausalView(BuildContext context, GameController c) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (context, scroll) =>
            _CausalSheet(controller: c, scrollController: scroll),
      ),
    );

class _CausalSheet extends StatelessWidget {
  const _CausalSheet({
    required this.controller,
    required this.scrollController,
  });

  final GameController controller;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final loops = controller.sim.loops;
        final strongest = loops.first.strength;
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(l10n.causalViewTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              l10n.causalViewIntro,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            for (final activity in loops)
              _LoopCard(
                activity: activity,
                // Only call something dominant when it actually leads; on a
                // quiet map every loop is near zero and none of them is.
                dominant:
                    activity.strength >= strongest && activity.strength > 0.05,
              ),
          ],
        );
      },
    );
  }
}

class _LoopCard extends StatelessWidget {
  const _LoopCard({required this.activity, required this.dominant});

  final LoopActivity activity;
  final bool dominant;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reinforcing = activity.polarity == LoopPolarity.reinforcing;
    return Card(
      elevation: dominant ? 2 : 0,
      color: dominant ? scheme.secondaryContainer : scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  reinforcing ? Icons.trending_up : Icons.sync_alt,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.causalLoopName(activity.loop.name),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (dominant)
                  Chip(
                    label: Text(l10n.causalDominant),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              l10n.causalPolarity(activity.polarity.name),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            _Chain(nodes: activity.nodes),
            const SizedBox(height: 8),
            Text(
              l10n.causalLoopStory(activity.loop.name),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: activity.strength.clamp(0.0, 1.0),
              // A reading, not a score: no percentage label, because the five
              // strengths are different quantities and inviting comparison by
              // number would be inviting a wrong comparison.
              semanticsLabel: l10n.causalLoopName(activity.loop.name),
            ),
          ],
        ),
      ),
    );
  }
}

/// The loop written out as steps, ending with an arrow back to the start.
class _Chain extends StatelessWidget {
  const _Chain({required this.nodes});

  final List<String> nodes;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final arrow = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Icon(
        Icons.arrow_right_alt,
        size: 16,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < nodes.length; i++) ...[
          if (i > 0) arrow,
          Text(
            l10n.causalNodeName(nodes[i]),
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        arrow,
        // The loop closes: the last step feeds the first.
        Text(
          l10n.causalNodeName(nodes.first),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}
