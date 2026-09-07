// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:stadtbau_sim/stadtbau_sim.dart';

import '../game/game_controller.dart';
import '../l10n/generated/app_localizations.dart';

/// Level goals with live progress and the remaining time.
class GoalsPanel extends StatelessWidget {
  const GoalsPanel({super.key, required this.controller, this.compact = false});

  final GameController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final level = controller.level;
        final progress = controller.progress;
        if (level == null || progress == null) return const SizedBox.shrink();
        final ind = controller.sim.indicators;
        final locale = Localizations.localeOf(context).toString();
        final n0 = NumberFormat.decimalPatternDigits(
          locale: locale,
          decimalDigits: 0,
        );
        final rows = [
          for (var i = 0; i < level.goals.length; i++)
            _GoalRow(
              text: controller.simpleMode
                  ? simpleGoalText(l10n, level.goals[i])
                  : goalText(l10n, level.goals[i], n0),
              current: n0.format(level.goals[i].current(ind)),
              met: progress.goalsMet[i],
              compact: compact,
              simpleMode: controller.simpleMode,
            ),
        ];
        final left = progress.monthsLeft;
        final header = Row(
          children: [
            Expanded(
              child: Text(l10n.goalsTitle, style: theme.textTheme.titleMedium),
            ),
            if (left != null)
              Text(l10n.monthsLeft(left), style: theme.textTheme.bodySmall),
          ],
        );
        final guidance = controller.goalGuidance;
        final guidanceCard = guidance == null
            ? null
            : _GuidanceCard(controller: controller, guidance: guidance);
        if (compact) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(
              children: [
                Wrap(spacing: 8, runSpacing: 2, children: [header, ...rows]),
                if (guidanceCard != null) guidanceCard,
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [header, ...rows, if (guidanceCard != null) guidanceCard],
          ),
        );
      },
    );
  }

  static String goalText(AppLocalizations l10n, LevelGoal g, NumberFormat n0) {
    final ind = g.indicator;
    if (ind != null) {
      return l10n.goalIndicator(l10n.indicatorName(ind.name), n0.format(g.min));
    }
    return l10n.goalMetric(g.metric ?? '', n0.format(g.min));
  }

  static String simpleGoalText(AppLocalizations l10n, LevelGoal goal) =>
      l10n.simpleGoal(goal.indicator?.name ?? goal.metric ?? '');
}

class _GoalRow extends StatelessWidget {
  const _GoalRow({
    required this.text,
    required this.current,
    required this.met,
    required this.compact,
    required this.simpleMode,
  });

  final String text;
  final String current;
  final bool met;
  final bool compact;
  final bool simpleMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = met
        ? const Color(0xFF2C7FB8)
        : theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      children: [
        Icon(
          met ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 4),
        if (compact)
          Text(
            simpleMode ? text : '$text ($current)',
            style: theme.textTheme.bodySmall,
          )
        else ...[
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
          if (!simpleMode)
            Text(
              current,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
        ],
      ],
    );
  }
}

class _GuidanceCard extends StatelessWidget {
  const _GuidanceCard({required this.controller, required this.guidance});

  final GameController controller;
  final GoalGuidance guidance;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final target = guidance.indicator == null
        ? l10n.goalMetricName(guidance.metric ?? '')
        : l10n.indicatorName(guidance.indicator!.name);
    final tile = guidance.tile;
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.lightbulb_outline),
        title: Text(l10n.guidanceNeedsAttention(target)),
        subtitle: Text(
          tile == null
              ? l10n.guidanceExplore
              : l10n.guidanceTryTile(l10n.tileName(tile.id)),
        ),
        trailing: tile == null ? null : const Icon(Icons.chevron_right),
        onTap: tile == null ? null : () => controller.setBrush(tile),
      ),
    );
  }
}
