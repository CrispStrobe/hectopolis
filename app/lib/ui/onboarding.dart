// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:stadtbau_sim/stadtbau_sim.dart';

import '../game/game_controller.dart';
import '../game/save_store.dart';
import '../l10n/generated/app_localizations.dart';
import 'tile_style.dart';

/// The three steps of the onboarding overlay (T-208). The ids are also the
/// `select` cases of `onboardingStepTitle` / `onboardingStepBody`.
enum OnboardingStep { tiles, overlays, loop }

/// Shows the onboarding overlay and records that the player has seen it.
///
/// The dialog is dismissible with Escape and by tapping outside; every way out
/// (Skip, Done, barrier, Escape) marks the flag, so it appears only once.
Future<void> showOnboarding(BuildContext context, SaveStore store) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const OnboardingDialog(),
  );
  await store.markOnboardingSeen();
}

/// A three-step tutorial: tiles, overlays and inspector, one feedback loop.
class OnboardingDialog extends StatefulWidget {
  const OnboardingDialog({super.key});

  @override
  State<OnboardingDialog> createState() => _OnboardingDialogState();
}

class _OnboardingDialogState extends State<OnboardingDialog> {
  int _index = 0;

  static const _steps = OnboardingStep.values;

  bool get _isLast => _index == _steps.length - 1;

  void _next() {
    if (_isLast) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _index++);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final step = _steps[_index];
    return AlertDialog(
      title: Text(l10n.onboardingTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.onboardingStepCounter(_index + 1, _steps.length),
                style: theme.textTheme.labelMedium?.copyWith(color: theme.hintColor),
              ),
              const SizedBox(height: 8),
              Text(l10n.onboardingStepTitle(step.name), style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(l10n.onboardingStepBody(step.name)),
              const SizedBox(height: 16),
              _StepIllustration(step: step),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _steps.length; i++)
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _index ? theme.colorScheme.primary : theme.dividerColor,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.onboardingSkip)),
        FilledButton(
          onPressed: _next,
          child: Text(_isLast ? l10n.onboardingDone : l10n.onboardingNext),
        ),
      ],
    );
  }
}

/// A small, wordless-as-possible picture per step: tile swatches, overlay
/// colour ramps, or the chips of one feedback loop.
class _StepIllustration extends StatelessWidget {
  const _StepIllustration({required this.step});

  final OnboardingStep step;

  @override
  Widget build(BuildContext context) => switch (step) {
        OnboardingStep.tiles => const _TilesIllustration(),
        OnboardingStep.overlays => const _OverlaysIllustration(),
        OnboardingStep.loop => const _LoopIllustration(),
      };
}

/// Three tiles from the palette and the grid they are dropped onto.
class _TilesIllustration extends StatelessWidget {
  const _TilesIllustration();

  static const _tiles = [TileType.forest, TileType.housingHigh, TileType.road];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Row(
      children: [
        for (final t in _tiles)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Tooltip(
              // Onboarding runs before any level is chosen, so there is
              // no sub-type to apply: these are the class names.
              message: l10n.tileName(t.id),
              child: _Swatch(color: TileStyle.of(t).color, icon: TileStyle.of(t).icon, iconColor: TileStyle.of(t).iconColor),
            ),
          ),
        Icon(Icons.arrow_right_alt, color: theme.hintColor),
        const SizedBox(width: 6),
        const _MiniMap(tiles: _tiles),
      ],
    );
  }
}

/// A 3 × 3 patch of the map with a few tiles placed on meadow.
class _MiniMap extends StatelessWidget {
  const _MiniMap({required this.tiles});

  final List<TileType> tiles;

  @override
  Widget build(BuildContext context) {
    final grid = <TileType>[
      TileType.meadow, tiles[0], TileType.meadow, //
      tiles[2], tiles[2], tiles[2], //
      TileType.meadow, tiles[1], TileType.meadow, //
    ];
    return SizedBox(
      width: 78,
      height: 78,
      child: GridView.count(
        crossAxisCount: 3,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (final t in grid)
            Container(
              margin: const EdgeInsets.all(0.5),
              color: TileStyle.of(t).color,
            ),
        ],
      ),
    );
  }
}

/// The layers button and the colour ramps it switches on.
class _OverlaysIllustration extends StatelessWidget {
  const _OverlaysIllustration();

  static const _overlays = [MapOverlay.noise, MapOverlay.air, MapOverlay.heat, MapOverlay.green];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final o in _overlays)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 92,
                  child: Text(l10n.overlayName(o.name), style: theme.textTheme.bodySmall),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: SizedBox(
                      height: 10,
                      child: Row(
                        children: [
                          for (var i = 0; i < 8; i++)
                            Expanded(
                              child: ColoredBox(
                                color: overlayColor(i / 7, highIsBad: o != MapOverlay.green),
                                child: const SizedBox(height: 10),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 2),
        Row(
          children: [
            Icon(Icons.layers, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Icon(Icons.touch_app, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(l10n.inspectorEmpty, style: theme.textTheme.bodySmall)),
          ],
        ),
      ],
    );
  }
}

/// One balancing loop: homes → residents → traffic → noise and air →
/// attractiveness, with forest and park as the damping element.
class _LoopIllustration extends StatelessWidget {
  const _LoopIllustration();

  static const _chain = ['homes', 'residents', 'traffic', 'noise', 'attractiveness'];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    const colors = [
      Color(0xFFFFAB91), // homes
      Color(0xFFFFE0B2), // residents and taxes
      Color(0xFF9E9E9E), // traffic
      Color(0xFFD95F0E), // noise and air
      Color(0xFF2C7FB8), // attractiveness
    ];
    const icons = [Icons.apartment, Icons.groups, Icons.directions_car, Icons.volume_up, Icons.favorite];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 4,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var i = 0; i < _chain.length; i++) ...[
              _Chip(label: l10n.onboardingLoopNode(_chain[i]), color: colors[i], icon: icons[i]),
              if (i < _chain.length - 1) Icon(Icons.arrow_right_alt, size: 18, color: theme.hintColor),
            ],
            Icon(Icons.subdirectory_arrow_left, size: 18, color: theme.hintColor),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.shield_moon_outlined, size: 18, color: theme.hintColor),
            const SizedBox(width: 6),
            _Chip(
              label: l10n.onboardingLoopNode('green'),
              color: TileStyle.of(TileType.forest).color,
              icon: Icons.forest,
            ),
          ],
        ),
      ],
    );
  }
}

/// A rounded colour swatch with a Material Symbols glyph.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.icon, required this.iconColor});

  final Color color;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) => Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
        child: Icon(icon, size: 20, color: iconColor),
      );
}

/// A labelled node of the feedback loop.
class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color, required this.icon});

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final onColor = ThemeData.estimateBrightnessForColor(color) == Brightness.dark ? Colors.white : Colors.black87;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: onColor),
          const SizedBox(width: 4),
          Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: onColor)),
        ],
      ),
    );
  }
}
