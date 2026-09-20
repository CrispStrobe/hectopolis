// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:stadtbau_sim/stadtbau_sim.dart';
import 'package:url_launcher/url_launcher.dart';

import '../game/game_controller.dart';
import '../l10n/generated/app_localizations.dart';
import 'doc_links.dart';

/// The fill of an indicator's bar at [value] (0-100): warm when a reading is
/// poor, cool when it is good.
///
/// The endpoints differ by theme because the bar has to stay distinguishable
/// from the track behind it (WCAG 1.4.11, 3:1), and the track is light in one
/// theme and dark in the other. One pair of colours could not do both: the
/// original single pair measured 2.91:1 on the light track at a reading of 0.
///
/// The endpoints were chosen by sweeping the *whole* scale, not by checking
/// the two ends, because the worst point is in the middle: a warm-to-cool
/// lerp passes through a desaturated tone whose luminance sits closest to the
/// track, and in dark mode that midpoint measured 2.73:1 while both ends
/// passed. `app/test/contrast_test.dart` sweeps every reading for this
/// reason.
Color indicatorBarColor(double value, {required bool dark}) => Color.lerp(
      dark ? const Color(0xFFF06D16) : const Color(0xFFCF5B0D),
      dark ? const Color(0xFF3490CE) : const Color(0xFF2A79B0),
      value.clamp(0, 100) / 100,
    )!;

/// Opens the detail sheet of one indicator: name, hint, current detail line,
/// how the score is computed and a link into `docs/model` (T-204).
Future<void> showIndicatorDetails(
  BuildContext context, {
  required Indicator indicator,
  required String detail,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) =>
        _IndicatorDetailsSheet(indicator: indicator, detail: detail),
  );
}

/// Ten gauges with a detail line each. Compact mode renders a horizontal strip.
class IndicatorPanel extends StatelessWidget {
  const IndicatorPanel({
    super.key,
    required this.controller,
    this.compact = false,
  });

  final GameController controller;
  final bool compact;

  MapOverlay? _overlayFor(Indicator i) => switch (i) {
    Indicator.biodiversity => MapOverlay.habitat,
    Indicator.air => MapOverlay.air,
    Indicator.noise => MapOverlay.noise,
    Indicator.housing => MapOverlay.attractiveness,
    Indicator.economy => MapOverlay.jobs,
    Indicator.shopping => MapOverlay.retail,
    Indicator.recreation => MapOverlay.green,
    Indicator.commuting => MapOverlay.traffic,
    Indicator.climate => MapOverlay.heat,
    // No runoff overlay yet; the heat layer at least shows the sealed ground
    // that sheds the rain, which is the thing to act on.
    Indicator.flood => MapOverlay.heat,
    Indicator.budget => null,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final ind = controller.sim.indicators;
        final locale = Localizations.localeOf(context).toString();
        final n0 = NumberFormat.decimalPatternDigits(
          locale: locale,
          decimalDigits: 0,
        );
        final n1 = NumberFormat.decimalPatternDigits(
          locale: locale,
          decimalDigits: 1,
        );
        final n2 = NumberFormat.decimalPatternDigits(
          locale: locale,
          decimalDigits: 2,
        );

        String detail(Indicator i) => switch (i) {
          Indicator.biodiversity => l10n.statsHabitat(
            n0.format(ind.habitatAreaEff),
            n2.format(ind.habitatConnectivity),
          ),
          Indicator.air => l10n.statsPopulation(n0.format(ind.population)),
          Indicator.flood => l10n.statsRunoff(
            n2.format(ind.meanRunoffMm),
            n0.format(ind.floodRiskCells),
          ),
          Indicator.noise => l10n.statsNoise(
            l10n.dbValue(n0.format(ind.meanNoiseDb)),
          ),
          Indicator.housing => l10n.statsPopulation(n0.format(ind.population)),
          Indicator.economy => l10n.statsJobs(
            n0.format(ind.jobsFilled),
            n0.format(ind.jobsCapacity),
          ),
          Indicator.shopping => l10n.statsPopulation(n0.format(ind.population)),
          Indicator.recreation => l10n.statsHeat(
            l10n.degreesValue(n1.format(ind.meanHeatDeltaC)),
          ),
          Indicator.commuting => l10n.statsCommute(
            l10n.kmValue(n1.format(ind.meanCommuteKm)),
            l10n.percentValue(n0.format(ind.carShare * 100)),
          ),
          Indicator.climate => l10n.tonsPerYear(n0.format(ind.co2TonsPerYear)),
          Indicator.budget => l10n.statsBudgetDelta(
            l10n.kEur(n0.format(ind.budgetDeltaKEur)),
          ),
        };

        final tiles = [
          for (final i in Indicator.values)
            _Gauge(
              indicator: i,
              label: l10n.indicatorName(i.name),
              hint: controller.simpleMode
                  ? l10n.indicatorSimpleHint(i.name)
                  : l10n.indicatorHint(i.name),
              detail: detail(i),
              value: ind.score(i),
              compact: compact,
              simpleMode: controller.simpleMode,
              history: controller.indicatorHistory,
              onTap: () {
                final overlay = _overlayFor(i);
                if (overlay != null) controller.setOverlay(overlay);
              },
            ),
        ];

        if (compact) {
          // Same shape and the same reason as the palette strip, which carries
          // the full note: a stated height clips the reading this exists to
          // show as soon as the system font grows. See palette.dart.
          return ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: IntrinsicHeight(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: tiles,
                ),
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(8),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.indicatorsTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    controller.simpleMode ? Icons.mood : Icons.analytics,
                  ),
                  tooltip: controller.simpleMode
                      ? l10n.indicatorModeExpert
                      : l10n.indicatorModeSimple,
                  onPressed: controller.toggleSimpleMode,
                ),
              ],
            ),
            ...tiles,
          ],
        );
      },
    );
  }
}

class _Gauge extends StatelessWidget {
  const _Gauge({
    required this.indicator,
    required this.label,
    required this.hint,
    required this.detail,
    required this.value,
    required this.compact,
    required this.simpleMode,
    required this.history,
    required this.onTap,
  });

  final Indicator indicator;
  final String label;
  final String hint;
  final String detail;
  final double value;
  final bool compact;
  final bool simpleMode;
  final List<IndicatorHistorySample> history;
  final VoidCallback onTap;

  void _open(BuildContext context) =>
      showIndicatorDetails(context, indicator: indicator, detail: detail);

  Color _color(BuildContext context) => indicatorBarColor(
        value,
        dark: Theme.of(context).brightness == Brightness.dark,
      );

  /// Simple mode's face for a score.
  ///
  /// Material icons rather than emoji: the icon font is already bundled and
  /// tree-shaken, and an emoji is not in Roboto, so every one of them made
  /// CanvasKit fetch a colour-emoji font from Google on the web
  /// (docs/web-payload.md). These also take the theme colour, which the
  /// emoji could not.
  IconData _smiley(double v) {
    if (v >= 0.8) return Icons.sentiment_very_satisfied;
    if (v >= 0.6) return Icons.sentiment_satisfied;
    if (v >= 0.4) return Icons.sentiment_neutral;
    if (v >= 0.2) return Icons.sentiment_dissatisfied;
    return Icons.sentiment_very_dissatisfied;
  }

  Color _smileyColor(double v) {
    if (v >= 0.8) return Colors.green.shade700;
    if (v >= 0.6) return Colors.lightGreen.shade600;
    if (v >= 0.4) return Colors.yellow.shade700;
    if (v >= 0.2) return Colors.orange.shade700;
    return Colors.red.shade900;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = value.clamp(0, 100) / 100;
    final rounded = value.clamp(0, 100).round();
    // The gauge is a bar, a number and, in simple mode, a smiley: none of
    // which a screen reader can read. One label carries the reading, and
    // mergeSemantics stops the parts being announced separately.
    final l10n = AppLocalizations.of(context);
    final spoken = l10n.a11yIndicatorValue(
      label,
      rounded.toString(),
      simpleMode ? hint : detail,
    );

    if (compact) {
      return Semantics(
        label: spoken,
        button: true,
        container: true,
        excludeSemantics: true,
        onTap: onTap,
        child: Tooltip(
          message: simpleMode ? hint : '$hint\n$detail',
          child: InkWell(
            onTap: () {
              onTap();
              if (!simpleMode) _open(context);
            },
            onLongPress: () => _open(context),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              width: 96,
              margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: theme.dividerColor),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall,
                  ),
                  simpleMode
                      ? Icon(_smiley(v), color: _smileyColor(v), size: 22)
                      : Text(
                          '$rounded',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: _color(context),
                          ),
                        ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Semantics(
      label: spoken,
      button: true,
      container: true,
      excludeSemantics: true,
      onTap: onTap,
      child: Tooltip(
        message: hint,
        waitDuration: const Duration(milliseconds: 600),
        child: InkWell(
          onTap: () {
            onTap();
            if (!simpleMode) _open(context);
          },
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(label, style: theme.textTheme.bodyMedium),
                    ),
                    if (simpleMode)
                      Icon(_smiley(v), color: _smileyColor(v), size: 22)
                    else ...[
                      Text(
                        '$rounded',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: _color(context),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.info_outline,
                        size: 14,
                        color: theme.hintColor,
                      ),
                    ],
                  ],
                ),
                if (!simpleMode) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: v,
                      minHeight: 8,
                      color: _color(context),
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                  Text(detail, style: theme.textTheme.bodySmall),
                  if (history.length > 1)
                    SizedBox(
                      height: 22,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: _SparklinePainter(
                          samples: history,
                          indicator: indicator,
                          color: _color(context),
                          eventColor: theme.colorScheme.secondary,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({
    required this.samples,
    required this.indicator,
    required this.color,
    required this.eventColor,
  });

  final List<IndicatorHistorySample> samples;
  final Indicator indicator;
  final Color color;
  final Color eventColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2 || size.isEmpty) return;
    final path = Path();
    for (var i = 0; i < samples.length; i++) {
      final x = size.width * i / (samples.length - 1);
      final score = (samples[i].scores[indicator] ?? 0).clamp(0.0, 100.0);
      final y = size.height * (1 - score / 100);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
        if (samples[i].tick == samples[i - 1].tick) {
          canvas.drawCircle(Offset(x, y), 1.8, Paint()..color = eventColor);
        }
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.7
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) => true;
}

/// Contents of the indicator detail sheet.
class _IndicatorDetailsSheet extends StatelessWidget {
  const _IndicatorDetailsSheet({required this.indicator, required this.detail});

  final Indicator indicator;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final url = indicatorDocUrl(indicator);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.indicatorName(indicator.name),
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(l10n.indicatorHint(indicator.name)),
              const SizedBox(height: 8),
              Text(detail, style: theme.textTheme.bodySmall),
              const SizedBox(height: 16),
              Text(
                l10n.indicatorFormulaLabel,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(l10n.indicatorFormula(indicator.name)),
              const SizedBox(height: 16),
              _DocLink(label: l10n.indicatorSourceLink, url: url),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.actionClose),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Underlined, tappable text that opens [url] in the browser.
class _DocLink extends StatelessWidget {
  const _DocLink({required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () async {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.open_in_new, size: 16, color: scheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: scheme.primary,
              decoration: TextDecoration.underline,
            ),
          ),
        ],
      ),
    );
  }
}
