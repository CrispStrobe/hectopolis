// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:stadtbau_sim/stadtbau_sim.dart';
import 'package:url_launcher/url_launcher.dart';

import '../game/game_controller.dart';
import '../l10n/generated/app_localizations.dart';

/// Base URL of the model documentation in the repository (T-204).
const indicatorDocsBaseUrl =
    'https://github.com/CrispStrobe/stadtbau/blob/main/docs/model/';

/// The model document that explains each indicator.
const indicatorDocFile = <Indicator, String>{
  Indicator.biodiversity: 'biodiversity.md',
  Indicator.air: 'air.md',
  Indicator.noise: 'noise.md',
  Indicator.housing: 'economy.md',
  Indicator.economy: 'economy.md',
  Indicator.shopping: 'access.md',
  Indicator.recreation: 'access.md',
  Indicator.commuting: 'commute.md',
  Indicator.climate: 'heat.md',
  Indicator.budget: 'economy.md',
};

/// The documentation URL for [indicator].
String indicatorDocUrl(Indicator indicator) =>
    '$indicatorDocsBaseUrl${indicatorDocFile[indicator]!}';

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
          return SizedBox(
            height: 64,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: tiles,
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

  Color _color(BuildContext context) {
    final v = value.clamp(0, 100) / 100;
    return Color.lerp(const Color(0xFFD95F0E), const Color(0xFF2C7FB8), v)!;
  }

  String _smiley(double v) {
    if (v >= 0.8) return '😄';
    if (v >= 0.6) return '🙂';
    if (v >= 0.4) return '😐';
    if (v >= 0.2) return '🙁';
    return '😠';
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

    if (compact) {
      return Tooltip(
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
                    ? Text(
                        _smiley(v),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: _smileyColor(v),
                        ),
                      )
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
      );
    }

    return Tooltip(
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
                    Text(
                      _smiley(v),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: _smileyColor(v),
                      ),
                    )
                  else ...[
                    Text(
                      '$rounded',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: _color(context),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.info_outline, size: 14, color: theme.hintColor),
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
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
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
