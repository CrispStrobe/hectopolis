// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:stadtbau_sim/stadtbau_sim.dart';

import '../game/build_features.dart';
import '../game/experience_settings.dart';
import '../game/game_controller.dart';
import '../l10n/generated/app_localizations.dart';
import 'about_screen.dart';
import 'causal_view.dart';
import 'goals_panel.dart';
import 'indicator_panel.dart';
import 'learning_center.dart';
import 'map_view.dart';
import 'palette.dart';
import 'tile_inspector.dart';
import 'tile_style.dart';

part 'game_screen/menus.dart';
part 'game_screen/overlay_controls.dart';
part 'game_screen/toolbar.dart';

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

  void _causalView() => showCausalView(context, c);

  /// Missions opt into the loop view individually (MissionFeature.causalView);
  /// the sandbox, which teaches nothing in particular, always offers it.
  bool get _causalViewAvailable {
    final learning = c.level?.learning;
    return learning == null || learning.has(MissionFeature.causalView);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Global, so that Tab-ing to a palette card or an app-bar button does not
    // silently disable the keyboard. Cursor keys stay with the map: they are
    // cell movement, and making them global would fight focus traversal.
    return CallbackShortcuts(
      bindings: _globalShortcuts(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Both breakpoints are about whether text fits, so both are in
          // text-sized units rather than pixels: at 200 % system font a
          // 1400 px window has the room of a 700 px one, and asking the
          // roomy app bar to lay its actions out inline there overflowed it
          // by 87 px. Dividing the width by the scale makes a large-text
          // desktop fall back to the same layouts a small window gets, which
          // is the behaviour those layouts already exist for.
          final textScale = MediaQuery.textScalerOf(context).scale(1);
          final effectiveWidth = constraints.maxWidth / textScale;
          final wide = effectiveWidth >= 1000;
          final roomyAppBar = effectiveWidth >= 1280;
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
                      if (c.level == null && !c.cooperative)
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
                        onNewGame: c.level == null && !c.cooperative
                            ? _newGame
                            : null,
                        onSettings: _settings,
                        onLocaleToggle: widget.onLocaleToggle,
                        onAbout: _about,
                        onKeyboardHelp: _showKeyboardHelp,
                        onCausalView: _causalViewAvailable ? _causalView : null,
                      ),
                    ],
            ),
            body: Column(
              children: [
                if (c.cooperative) _CoopTurnBanner(controller: c),
                Expanded(child: wide ? _wide() : _narrow()),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Shortcuts that work wherever the focus happens to be.
  ///
  /// Digits, undo/redo and Escape are about the game rather than about the
  /// map, so they should not depend on the map holding the keyboard. The app
  /// has no text input anywhere, so bare digits are unambiguous.
  Map<ShortcutActivator, VoidCallback> _globalShortcuts() {
    const digits = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
      LogicalKeyboardKey.digit0,
    ];
    return {
      for (var i = 0; i < digits.length; i++)
        SingleActivator(digits[i]): () => c.selectBrushByIndex(i),
      const SingleActivator(LogicalKeyboardKey.escape): c.clearBrush,
      const SingleActivator(LogicalKeyboardKey.keyZ, control: true): c.undo,
      const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): c.undo,
      const SingleActivator(
        LogicalKeyboardKey.keyZ,
        control: true,
        shift: true,
      ): c.redo,
      const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
          c.redo,
      const SingleActivator(LogicalKeyboardKey.keyY, control: true): c.redo,
      const SingleActivator(LogicalKeyboardKey.slash, shift: true):
          _showKeyboardHelp,
      const SingleActivator(LogicalKeyboardKey.f1): _showKeyboardHelp,
    };
  }

  void _showKeyboardHelp() {
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.keyboard),
        title: Text(l10n.keyboardShortcutsTitle),
        content: Text(l10n.keyboardHint),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.actionClose),
          ),
        ],
      ),
    ).then((_) => c.requestMapFocus());
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
