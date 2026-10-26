// SPDX-License-Identifier: AGPL-3.0-or-later
part of '../game_screen.dart';

class _Clock extends StatelessWidget {
  const _Clock({required this.controller, this.compact = false});
  final GameController controller;

  /// Narrow layouts drop the date; it is still visible in the goals panel and
  /// the inspector, and the app bar has no room for it.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final n0 = NumberFormat.decimalPatternDigits(
      locale: locale,
      decimalDigits: 0,
    );
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final s = controller.sim.state;
        final ind = controller.sim.indicators;
        final year = s.tick ~/ 12 + 1;
        final month = s.tick % 12 + 1;
        if (controller.simpleMode) {
          final average =
              Indicator.values.fold<double>(
                0,
                (sum, indicator) => sum + ind.score(indicator),
              ) /
              Indicator.values.length;
          // Material icons, not emoji: see docs/web-payload.md.
          final face = average >= 75
              ? Icons.sentiment_very_satisfied
              : average >= 55
              ? Icons.sentiment_satisfied
              : average >= 35
              ? Icons.sentiment_neutral
              : Icons.sentiment_dissatisfied;
          return Row(
            children: [
              if (!compact) Text(l10n.yearMonthLabel(year, month)),
              if (!compact) const SizedBox(width: 10),
              Tooltip(message: l10n.townMood, child: Icon(face, size: 22)),
            ],
          );
        }
        return Row(
          children: [
            if (!compact) ...[
              Text(l10n.yearMonthLabel(year, month)),
              const SizedBox(width: 12),
            ],
            Tooltip(
              message: l10n.budgetLabel,
              child: Text(l10n.kEur(n0.format(s.budgetKEur))),
            ),
            const SizedBox(width: 12),
            Tooltip(
              message: l10n.populationLabel,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(n0.format(ind.population)),
                  const SizedBox(width: 4),
                  const Icon(Icons.group, size: 16),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport({required this.controller, this.compact = false});
  final GameController controller;

  /// Narrow layouts show only play/pause and step; speeds live in [_MoreMenu].
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.cooperative) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!compact) Text(l10n.coopRound(controller.cooperativeRound)),
              IconButton(
                tooltip: l10n.coopEndTurn,
                icon: const Icon(Icons.done_all),
                onPressed: controller.isMyTurn ? controller.step : null,
              ),
            ],
          );
        }
        return Row(
          children: [
            IconButton(
              tooltip: controller.speed == 0
                  ? l10n.actionPlay
                  : l10n.actionPause,
              icon: Icon(
                controller.speed == 0 ? Icons.play_arrow : Icons.pause,
              ),
              onPressed: controller.togglePlay,
            ),
            IconButton(
              tooltip: l10n.actionStep,
              icon: const Icon(Icons.skip_next),
              onPressed: controller.step,
            ),
            if (!compact)
              for (final s in GameController.speeds)
                IconButton(
                  tooltip: l10n.actionSpeed(s),
                  isSelected: controller.speed == s,
                  icon: Text('$s×'),
                  onPressed: () => controller.setSpeed(s),
                ),
          ],
        );
      },
    );
  }
}

class _HistoryControls extends StatelessWidget {
  const _HistoryControls({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: l10n.actionUndo,
            icon: const Icon(Icons.undo),
            onPressed: controller.canUndo ? controller.undo : null,
          ),
          IconButton(
            tooltip: l10n.actionRedo,
            icon: const Icon(Icons.redo),
            onPressed: controller.canRedo ? controller.redo : null,
          ),
        ],
      ),
    );
  }
}

class _CoopTurnBanner extends StatelessWidget {
  const _CoopTurnBanner({required this.controller});
  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        if (controller.cooperativeDisconnected) {
          return Material(
            color: scheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.wifi_off, color: scheme.onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(child: Text(l10n.coopConnectionLost)),
                  FilledButton.tonal(
                    onPressed: () async {
                      final ok = await controller.reconnectCooperative();
                      if (!ok && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              relayEnabled
                                  ? l10n.coopConnectionFailedRelay
                                  : l10n.coopConnectionFailed,
                            ),
                          ),
                        );
                      }
                    },
                    child: Text(l10n.coopReconnect),
                  ),
                ],
              ),
            ),
          );
        }
        final current = controller.cooperativePlayers
            .where((player) => player.id == controller.currentPlayerId)
            .firstOrNull;
        final text = controller.isMyTurn
            ? l10n.coopYourTurn
            : l10n.coopWaitingTurn(current?.name ?? l10n.lobbyWaiting);
        return Material(
          color: controller.isMyTurn
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          child: SafeArea(
            top: false,
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(controller.isMyTurn ? Icons.edit : Icons.hourglass_top),
                  const SizedBox(width: 8),
                  Expanded(child: Text(text)),
                  Text(l10n.coopRound(controller.cooperativeRound)),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: controller.isMyTurn ? controller.step : null,
                    child: Text(l10n.coopEndTurn),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
