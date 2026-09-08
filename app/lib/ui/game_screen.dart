// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:stadtbau_sim/stadtbau_sim.dart';

import '../game/experience_settings.dart';
import '../game/game_controller.dart';
import '../l10n/generated/app_localizations.dart';
import 'about_screen.dart';
import 'goals_panel.dart';
import 'indicator_panel.dart';
import 'learning_center.dart';
import 'map_view.dart';
import 'palette.dart';
import 'tile_inspector.dart';
import 'tile_style.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.controller,
    required this.onLocaleToggle,
  });

  final GameController controller;
  final VoidCallback onLocaleToggle;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  GameController get c => widget.controller;
  CommandError? _shownError;

  /// Zoom/pan state, shared between the map and the app-bar buttons (T-202).
  final _map = MapViewController();

  @override
  void initState() {
    super.initState();
    c.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && c.missionBriefingPending) {
        showMissionBriefing(context, c);
      }
    });
  }

  @override
  void dispose() {
    c.removeListener(_onChanged);
    _map.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (c.endPending) {
      c.acknowledgeEnd();
      WidgetsBinding.instance.addPostFrameCallback((_) => _showEnd());
    }
    final err = c.lastError;
    if (err != null && err != _shownError) {
      _shownError = err;
      final l10n = AppLocalizations.of(context);
      final text = switch (err) {
        CommandError.outOfBounds => l10n.errorOutOfBounds,
        CommandError.insufficientBudget => l10n.errorInsufficientBudget,
        CommandError.tileNotAllowed => l10n.errorTileNotAllowed,
        CommandError.tileExhausted => l10n.errorTileExhausted,
        CommandError.sameTile => null,
      };
      if (text != null) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
          );
      }
      c.lastError = null;
      _shownError = null;
    }
  }

  Future<void> _showEnd() async {
    final l10n = AppLocalizations.of(context);
    final level = c.level;
    final progress = c.progress;
    if (level == null || progress == null) return;
    final back = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          progress.allMet ? l10n.endTitleSuccess : l10n.endTitleTimeUp,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CelebrationStars(
              stars: progress.stars,
              animate:
                  c.experience.effectAnimations &&
                  !(MediaQuery.maybeOf(context)?.disableAnimations ?? false),
            ),
            const SizedBox(height: 8),
            Text(l10n.endGoalsMet(progress.metCount, progress.goalsMet.length)),
            MissionDebrief(controller: c),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.actionKeepPlaying),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.actionBackToLevels),
          ),
        ],
      ),
    );
    if (back == true && mounted) Navigator.of(context).pop();
  }

  Future<void> _newGame() async {
    final l10n = AppLocalizations.of(context);
    var w = c.width;
    var h = c.height;
    final result = await showDialog<List<int>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(l10n.newGameTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.newGameSize(w, h)),
              Row(
                children: [
                  const Text('X'), // i18n-ignore: mathematical axis label
                  Expanded(
                    child: Slider(
                      value: w.toDouble(),
                      min: 8,
                      max: 64,
                      divisions: 14,
                      label: '$w',
                      onChanged: (v) => setState(() => w = v.round()),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  const Text('Y'), // i18n-ignore: mathematical axis label
                  Expanded(
                    child: Slider(
                      value: h.toDouble(),
                      min: 8,
                      max: 64,
                      divisions: 14,
                      label: '$h',
                      onChanged: (v) => setState(() => h = v.round()),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, [w, h]),
              child: Text(l10n.ok),
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      c.startSandbox(result[0], result[1]);
      _map.reset();
    }
  }

  void _about() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const AboutScreen()));
  }

  void _settings() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _ExperienceSheet(controller: c),
    );
  }

  void _learning() => showLearningCenter(context, c);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1000;
        final roomyAppBar = constraints.maxWidth >= 1280;
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: l10n.actionBackToLevels,
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            title: Text(
              c.level == null
                  ? l10n.levelTitle('sandbox')
                  : l10n.levelTitle(c.level!.id),
            ),
            actions: roomyAppBar
                ? [
                    _Clock(controller: c),
                    const SizedBox(width: 8),
                    _Transport(controller: c),
                    _HistoryControls(controller: c),
                    _OverlayMenu(controller: c),
                    IconButton(
                      tooltip: l10n.actionZoomOut,
                      icon: const Icon(Icons.zoom_out),
                      onPressed: _map.zoomOut,
                    ),
                    IconButton(
                      tooltip: l10n.actionZoomIn,
                      icon: const Icon(Icons.zoom_in),
                      onPressed: _map.zoomIn,
                    ),
                    IconButton(
                      tooltip: l10n.actionZoomReset,
                      icon: const Icon(Icons.center_focus_strong),
                      onPressed: _map.reset,
                    ),
                    if (c.level == null)
                      IconButton(
                        tooltip: l10n.actionNewGame,
                        icon: const Icon(Icons.restart_alt),
                        onPressed: _newGame,
                      ),
                    IconButton(
                      tooltip: l10n.actionMissionNotebook,
                      icon: const Icon(Icons.school_outlined),
                      onPressed: c.level?.learning == null ? null : _learning,
                    ),
                    IconButton(
                      tooltip: l10n.actionExperienceSettings,
                      icon: const Icon(Icons.tune),
                      onPressed: _settings,
                    ),
                    IconButton(
                      tooltip: l10n.actionLanguage,
                      icon: const Icon(Icons.translate),
                      onPressed: widget.onLocaleToggle,
                    ),
                    IconButton(
                      tooltip: l10n.actionAbout,
                      icon: const Icon(Icons.info_outline),
                      onPressed: _about,
                    ),
                  ]
                : [
                    _Clock(controller: c, compact: true),
                    _Transport(controller: c, compact: true),
                    _OverlayMenu(controller: c),
                    if (c.level?.learning != null)
                      IconButton(
                        tooltip: l10n.actionMissionNotebook,
                        icon: const Icon(Icons.school_outlined),
                        onPressed: _learning,
                      ),
                    _MoreMenu(
                      controller: c,
                      map: _map,
                      onNewGame: c.level == null ? _newGame : null,
                      onSettings: _settings,
                      onLocaleToggle: widget.onLocaleToggle,
                      onAbout: _about,
                    ),
                  ],
          ),
          body: wide ? _wide() : _narrow(),
        );
      },
    );
  }

  Widget _wide() => Row(
    children: [
      SizedBox(width: 260, child: Palette(controller: c)),
      const VerticalDivider(width: 1),
      Expanded(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: MapView(controller: c, mapController: _map),
              ),
            ),
            _Legend(controller: c),
          ],
        ),
      ),
      const VerticalDivider(width: 1),
      SizedBox(
        width: 320,
        child: Column(
          children: [
            GoalsPanel(controller: c),
            if (c.level != null) const Divider(height: 1),
            Expanded(flex: 3, child: IndicatorPanel(controller: c)),
            const Divider(height: 1),
            Expanded(flex: 2, child: TileInspector(controller: c)),
          ],
        ),
      ),
    ],
  );

  Widget _narrow() => Column(
    children: [
      GoalsPanel(controller: c, compact: true),
      IndicatorPanel(controller: c, compact: true),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: MapView(controller: c, mapController: _map),
        ),
      ),
      _Legend(controller: c),
      SizedBox(height: 140, child: TileInspector(controller: c)),
      Palette(controller: c, horizontal: true),
    ],
  );
}

class _CelebrationStars extends StatelessWidget {
  const _CelebrationStars({required this.stars, required this.animate});

  final int stars;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    Widget row(double scale) => Transform.scale(
      scale: scale,
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          for (var i = 0; i < 3; i++)
            Icon(
              i < stars ? Icons.star : Icons.star_border,
              color: Colors.amber.shade700,
              size: 32,
            ),
        ],
      ),
    );
    if (!animate) return row(1);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.35, end: 1),
      duration: const Duration(milliseconds: 750),
      curve: Curves.elasticOut,
      builder: (context, value, _) => row(value),
    );
  }
}

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
          final face = average >= 75
              ? '😄'
              : average >= 55
              ? '🙂'
              : average >= 35
              ? '😐'
              : '🙁';
          return Row(
            children: [
              if (!compact) Text(l10n.yearMonthLabel(year, month)),
              if (!compact) const SizedBox(width: 10),
              Tooltip(
                message: l10n.townMood,
                child: Text(face, style: const TextStyle(fontSize: 22)),
              ),
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
              child: Text('${n0.format(ind.population)} 👥'),
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
      builder: (context, _) => Row(
        children: [
          IconButton(
            tooltip: controller.speed == 0 ? l10n.actionPlay : l10n.actionPause,
            icon: Icon(controller.speed == 0 ? Icons.play_arrow : Icons.pause),
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
      ),
    );
  }
}

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
                  '${l10n.overlayName(controller.overlay.name)} (${l10n.overlayUnit(controller.overlay.name)})',
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

/// Overflow menu for narrow layouts: speeds, zoom, new game, language, about.
class _MoreMenu extends StatelessWidget {
  const _MoreMenu({
    required this.controller,
    required this.map,
    required this.onNewGame,
    required this.onSettings,
    required this.onLocaleToggle,
    required this.onAbout,
  });

  final GameController controller;
  final MapViewController map;
  final VoidCallback? onNewGame;
  final VoidCallback onSettings;
  final VoidCallback onLocaleToggle;
  final VoidCallback onAbout;

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
