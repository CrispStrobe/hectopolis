// SPDX-License-Identifier: AGPL-3.0-or-later
part of '../game_screen.dart';

class _OverlayMenu extends StatelessWidget {
  const _OverlayMenu({required this.controller});
  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => PopupMenuButton<MapOverlay>(
        tooltip: l10n.overlayLabel,
        icon: Icon(
          controller.overlay == MapOverlay.none
              ? Icons.layers_outlined
              : Icons.layers,
        ),
        initialValue: controller.overlay,
        onSelected: controller.setOverlay,
        itemBuilder: (context) => [
          for (final o in MapOverlay.values)
            PopupMenuItem(
              value: o,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  controller.overlay == o
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: Text(l10n.overlayName(o.name)),
                subtitle: o == MapOverlay.none
                    ? null
                    : Text(
                        controller.overlayHighIsBadFor(o)
                            ? l10n.overlayDirectionHarmful
                            : l10n.overlayDirectionHelpful,
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.controller});
  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.overlay == MapOverlay.none) {
          return const SizedBox(height: 4);
        }
        final bad = controller.overlayHighIsBad;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Flexible(
                flex: 2,
                child: Text(
                  '${l10n.overlayName(controller.overlay.name)} '
                  '(${l10n.overlayUnit(controller.overlay.name)})'
                  '${controller.overlayThreshold == null || controller.showExperimentDelta ? '' : ' · ${l10n.overlayThresholdMarker}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                controller.showExperimentDelta
                    ? l10n.legendComparedWorse
                    : controller.simpleMode
                    ? (bad ? l10n.legendBetter : l10n.legendLess)
                    : l10n.legendLow,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Container(
                  height: 12,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        for (var i = 0; i <= 4; i++)
                          overlayColor(i / 4, highIsBad: bad),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                controller.showExperimentDelta
                    ? l10n.legendComparedBetter
                    : controller.simpleMode
                    ? (bad ? l10n.legendWorse : l10n.legendMore)
                    : l10n.legendHigh,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: l10n.overlayClose,
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => controller.setOverlay(MapOverlay.none),
              ),
            ],
          ),
        );
      },
    );
  }
}
