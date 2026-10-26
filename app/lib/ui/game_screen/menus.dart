// SPDX-License-Identifier: AGPL-3.0-or-later
part of '../game_screen.dart';

/// Overflow menu for narrow layouts: speeds, zoom, new game, language, about.
class _MoreMenu extends StatelessWidget {
  const _MoreMenu({
    required this.controller,
    required this.map,
    required this.onNewGame,
    required this.onSettings,
    required this.onLocaleToggle,
    required this.onAbout,
    required this.onKeyboardHelp,
    required this.onCausalView,
  });

  final GameController controller;
  final MapViewController map;
  final VoidCallback? onNewGame;
  final VoidCallback onSettings;
  final VoidCallback onLocaleToggle;
  final VoidCallback onAbout;
  final VoidCallback onKeyboardHelp;
  final VoidCallback? onCausalView;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => PopupMenuButton<VoidCallback>(
        tooltip: l10n.actionMore,
        icon: const Icon(Icons.more_vert),
        onSelected: (action) => action(),
        itemBuilder: (context) => [
          if (onCausalView case final open?)
            PopupMenuItem(
              value: open,
              child: ListTile(
                leading: const Icon(Icons.hub_outlined),
                title: Text(l10n.causalViewTitle),
              ),
            ),
          PopupMenuItem(
            value: onKeyboardHelp,
            child: ListTile(
              leading: const Icon(Icons.keyboard),
              title: Text(l10n.keyboardShortcutsTitle),
            ),
          ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: controller.undo,
            enabled: controller.canUndo,
            child: ListTile(
              leading: const Icon(Icons.undo),
              title: Text(l10n.actionUndo),
            ),
          ),
          PopupMenuItem(
            value: controller.redo,
            enabled: controller.canRedo,
            child: ListTile(
              leading: const Icon(Icons.redo),
              title: Text(l10n.actionRedo),
            ),
          ),
          const PopupMenuDivider(),
          for (final s in GameController.speeds)
            PopupMenuItem(
              value: () => controller.setSpeed(s),
              child: ListTile(
                leading: Icon(
                  controller.speed == s
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: Text(l10n.actionSpeed(s)),
              ),
            ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: map.zoomIn,
            child: ListTile(
              leading: const Icon(Icons.zoom_in),
              title: Text(l10n.actionZoomIn),
            ),
          ),
          PopupMenuItem(
            value: map.zoomOut,
            child: ListTile(
              leading: const Icon(Icons.zoom_out),
              title: Text(l10n.actionZoomOut),
            ),
          ),
          PopupMenuItem(
            value: map.reset,
            child: ListTile(
              leading: const Icon(Icons.center_focus_strong),
              title: Text(l10n.actionZoomReset),
            ),
          ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: onSettings,
            child: ListTile(
              leading: const Icon(Icons.tune),
              title: Text(l10n.actionExperienceSettings),
            ),
          ),
          if (onNewGame != null)
            PopupMenuItem(
              value: onNewGame!,
              child: ListTile(
                leading: const Icon(Icons.restart_alt),
                title: Text(l10n.actionNewGame),
              ),
            ),
          PopupMenuItem(
            value: onLocaleToggle,
            child: ListTile(
              leading: const Icon(Icons.translate),
              title: Text(l10n.actionLanguage),
            ),
          ),
          PopupMenuItem(
            value: onAbout,
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(l10n.actionAbout),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExperienceSheet extends StatelessWidget {
  const _ExperienceSheet({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final value = controller.experience;
          void update(ExperienceSettings next) =>
              controller.setExperience(next);
          return ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.experienceTitle,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(l10n.experienceDescription),
                  const SizedBox(height: 8),
                  Text(
                    l10n.learningModeLabel,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<LearningMode>(
                    showSelectedIcon: false,
                    segments: [
                      for (final mode in LearningMode.values)
                        ButtonSegment(
                          value: mode,
                          icon: Icon(switch (mode) {
                            LearningMode.starter => Icons.child_care,
                            LearningMode.guided => Icons.lightbulb_outline,
                            LearningMode.explorer => Icons.science_outlined,
                          }),
                          label: Text(l10n.learningModeName(mode.name)),
                        ),
                    ],
                    selected: {value.learningMode},
                    onSelectionChanged: (modes) =>
                        controller.setLearningMode(modes.single),
                  ),
                  const SizedBox(height: 6),
                  Text(l10n.learningModeDescription(value.learningMode.name)),
                  SwitchListTile(
                    secondary: const Icon(Icons.filter_none),
                    title: Text(l10n.settingCleanVisuals),
                    subtitle: Text(l10n.settingCleanVisualsDescription),
                    value: value.cleanVisuals,
                    onChanged: (enabled) =>
                        update(value.copyWith(cleanVisuals: enabled)),
                  ),
                  const Divider(),
                  SwitchListTile(
                    secondary: const Icon(Icons.air),
                    title: Text(l10n.settingAmbientAnimations),
                    subtitle: Text(l10n.settingAmbientAnimationsDescription),
                    value: value.ambientAnimations,
                    onChanged: (enabled) =>
                        update(value.copyWith(ambientAnimations: enabled)),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 24),
                    child: Column(
                      children: [
                        SwitchListTile(
                          secondary: const Icon(Icons.traffic),
                          title: Text(l10n.settingTrafficAnimations),
                          value: value.trafficAnimations,
                          onChanged: value.ambientAnimations
                              ? (enabled) => update(
                                  value.copyWith(trafficAnimations: enabled),
                                )
                              : null,
                        ),
                        SwitchListTile(
                          secondary: const Icon(Icons.water),
                          title: Text(l10n.settingEnvironmentAnimations),
                          value: value.environmentAnimations,
                          onChanged: value.ambientAnimations
                              ? (enabled) => update(
                                  value.copyWith(
                                    environmentAnimations: enabled,
                                  ),
                                )
                              : null,
                        ),
                        SwitchListTile(
                          secondary: const Icon(Icons.apartment),
                          title: Text(l10n.settingCityActivityAnimations),
                          value: value.cityActivityAnimations,
                          onChanged: value.ambientAnimations
                              ? (enabled) => update(
                                  value.copyWith(
                                    cityActivityAnimations: enabled,
                                  ),
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.animation),
                    title: Text(l10n.settingEffectAnimations),
                    subtitle: Text(l10n.settingEffectAnimationsDescription),
                    value: value.effectAnimations,
                    onChanged: (enabled) =>
                        update(value.copyWith(effectAnimations: enabled)),
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.auto_graph),
                    title: Text(l10n.settingPlacementForecasts),
                    subtitle: Text(l10n.settingPlacementForecastsDescription),
                    value: value.placementForecasts,
                    onChanged: (enabled) =>
                        update(value.copyWith(placementForecasts: enabled)),
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.hub_outlined),
                    title: Text(l10n.settingCausalHighlights),
                    subtitle: Text(l10n.settingCausalHighlightsDescription),
                    value: value.causalHighlights,
                    onChanged: (enabled) =>
                        update(value.copyWith(causalHighlights: enabled)),
                  ),
                  const Divider(),
                  SwitchListTile(
                    secondary: const Icon(Icons.volume_up_outlined),
                    title: Text(l10n.settingSoundEffects),
                    value: value.soundEffects,
                    onChanged: (enabled) =>
                        update(value.copyWith(soundEffects: enabled)),
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.vibration),
                    title: Text(l10n.settingHaptics),
                    value: value.haptics,
                    onChanged: (enabled) =>
                        update(value.copyWith(haptics: enabled)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
