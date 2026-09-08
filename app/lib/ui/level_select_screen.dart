// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:stadtbau_sim/stadtbau_sim.dart';

import '../game/game_controller.dart';
import '../game/save_store.dart';
import '../l10n/generated/app_localizations.dart';
import 'about_screen.dart';
import 'game_screen.dart';
import 'onboarding.dart';

/// Home screen: continue the autosave, play the sandbox or pick a level.
class LevelSelectScreen extends StatefulWidget {
  const LevelSelectScreen({
    super.key,
    required this.controller,
    required this.store,
    required this.onLocaleToggle,
  });

  final GameController controller;
  final SaveStore store;
  final VoidCallback onLocaleToggle;

  @override
  State<LevelSelectScreen> createState() => _LevelSelectScreenState();
}

class _LevelSelectScreenState extends State<LevelSelectScreen> {
  Map<String, int> _stars = {};
  Map<String, Set<String>> _medals = {};
  bool _hasSave = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowOnboarding());
  }

  /// On the very first launch, explain the game once (T-208).
  Future<void> _maybeShowOnboarding() async {
    if (await widget.store.onboardingSeen()) return;
    if (!mounted) return;
    await showOnboarding(context, widget.store);
  }

  Future<void> _refresh() async {
    await widget.controller.loadExperienceSettings();
    final stars = await widget.store.bestStars();
    final medals = await widget.store.earnedMedals();
    final save = await widget.store.load();
    if (!mounted) return;
    setState(() {
      _stars = stars;
      _medals = medals;
      _hasSave = save != null;
    });
  }

  Future<void> _open() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(
          controller: widget.controller,
          onLocaleToggle: widget.onLocaleToggle,
        ),
      ),
    );
    await _refresh();
  }

  Future<void> _continue() async {
    if (await widget.controller.restore()) await _open();
  }

  void _sandbox() {
    widget.controller.startSandbox(16, 16);
    _open();
  }

  void _level(Level l) {
    widget.controller.startLevel(l);
    _open();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          IconButton(
            tooltip: l10n.actionHelp,
            icon: const Icon(Icons.help_outline),
            onPressed: () => showOnboarding(context, widget.store),
          ),
          IconButton(
            tooltip: l10n.actionLanguage,
            icon: const Icon(Icons.translate),
            onPressed: widget.onLocaleToggle,
          ),
          IconButton(
            tooltip: l10n.actionAbout,
            icon: const Icon(Icons.info_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AboutScreen()),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(l10n.levelSelectTitle, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 12),
              if (_hasSave)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.play_circle),
                    title: Text(l10n.actionContinue),
                    onTap: _continue,
                  ),
                ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.grid_on),
                  title: Text(l10n.levelTitle('sandbox')),
                  subtitle: Text(l10n.levelDescription('sandbox')),
                  onTap: _sandbox,
                ),
              ),
              for (final l in Level.builtIn())
                Card(
                  child: ListTile(
                    leading: _Stars(count: _stars[l.id] ?? 0),
                    title: Text(l10n.levelTitle(l.id)),
                    trailing: (_medals[l.id]?.isNotEmpty ?? false)
                        ? Tooltip(
                            message: l10n.medalsEarned(_medals[l.id]!.length),
                            child: Badge(
                              label: Text('${_medals[l.id]!.length}'),
                              child: const Icon(Icons.emoji_events),
                            ),
                          )
                        : null,
                    subtitle: Text(
                      '${l10n.levelDescription(l.id)}\n'
                      '${l10n.goalsSummary(l.goals.length, l.turnLimitMonths ?? 0)}'
                      '${l.learning == null ? '' : ' · ${l10n.learningModeName(l.learning!.tier.name)}'}',
                    ),
                    isThreeLine: true,
                    onTap: () => _level(l),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < 3; i++)
        Icon(
          i < count ? Icons.star : Icons.star_border,
          size: 18,
          color: Colors.amber.shade700,
        ),
    ],
  );
}
