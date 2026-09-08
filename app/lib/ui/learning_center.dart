// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:stadtbau_sim/stadtbau_sim.dart';
import 'package:url_launcher/url_launcher.dart';

import '../game/experience_settings.dart';
import '../game/game_controller.dart';
import '../l10n/generated/app_localizations.dart';

const _modelDocsUrl =
    'https://github.com/CrispStrobe/stadtbau/tree/main/docs/model';

List<String> _predictionChoices(String predictionId) => switch (predictionId) {
  'village_access' => const ['near', 'far', 'balance'],
  'noise_homes' => const ['near', 'far', 'shield'],
  'habitat_corridor' => const ['connect', 'scatter', 'cut'],
  'budget_recovery' => const ['income', 'decorate', 'roads'],
  _ => const ['balance', 'far', 'near'],
};

class MissionDebrief extends StatelessWidget {
  const MissionDebrief({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final history = controller.indicatorHistory;
    final learning = controller.level?.learning;
    if (learning == null ||
        !learning.has(MissionFeature.debrief) ||
        history.isEmpty) {
      return const SizedBox.shrink();
    }
    final first = history.first.scores;
    final last = history.last.scores;
    final changes = [
      for (final indicator in Indicator.values)
        MapEntry(indicator, (last[indicator] ?? 0) - (first[indicator] ?? 0)),
    ]..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    final locale = Localizations.localeOf(context).toString();
    final format = NumberFormat.decimalPatternDigits(
      locale: locale,
      decimalDigits: 0,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Text(l10n.debriefTitle, style: Theme.of(context).textTheme.titleMedium),
        Text(l10n.debriefPrompt),
        if (controller.missionPrediction != null)
          Text(
            l10n.debriefPrediction(
              l10n.missionPredictionChoice(controller.missionPrediction!),
            ),
          ),
        const SizedBox(height: 6),
        for (final change in changes.take(3))
          Text(
            controller.simpleMode
                ? '${change.value >= 0 ? '😊' : '🤔'} '
                      '${l10n.indicatorName(change.key.name)}'
                : '${l10n.indicatorName(change.key.name)}: '
                      '${change.value >= 0 ? '+' : ''}${format.format(change.value)}',
          ),
      ],
    );
  }
}

Future<void> showMissionBriefing(
  BuildContext context,
  GameController controller,
) async {
  final learning = controller.level?.learning;
  if (learning == null) return;
  final l10n = AppLocalizations.of(context);
  String? prediction = controller.missionPrediction;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final predictionId = learning.predictionId;
        return AlertDialog(
          icon: const Icon(Icons.explore_outlined),
          title: Text(l10n.missionBriefingTitle),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.levelDescription(controller.level!.id)),
                  const SizedBox(height: 12),
                  Text(l10n.missionBriefingBody),
                  if (predictionId != null &&
                      learning.has(MissionFeature.prediction)) ...[
                    const SizedBox(height: 20),
                    Text(
                      l10n.missionPredictionTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(l10n.missionPredictionPrompt(predictionId)),
                    const SizedBox(height: 8),
                    RadioGroup<String>(
                      groupValue: prediction,
                      onChanged: (value) => setState(() => prediction = value),
                      child: Column(
                        children: [
                          for (final choice in _predictionChoices(predictionId))
                            RadioListTile<String>(
                              contentPadding: EdgeInsets.zero,
                              title: Text(l10n.missionPredictionChoice(choice)),
                              value: choice,
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.onboardingSkip),
            ),
            FilledButton(
              onPressed: () {
                if (prediction != null) {
                  controller.answerMissionPrediction(prediction!);
                }
                Navigator.pop(context);
              },
              child: Text(l10n.onboardingDone),
            ),
          ],
        );
      },
    ),
  );
  controller.acknowledgeMissionBriefing();
}

void showLearningCenter(BuildContext context, GameController controller) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _LearningCenter(controller: controller),
  );
}

class _LearningCenter extends StatelessWidget {
  const _LearningCenter({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final learning = controller.level?.learning;
    if (learning == null) return const SizedBox.shrink();
    return SafeArea(
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 680,
            maxHeight: MediaQuery.sizeOf(context).height * 0.9,
          ),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            children: [
              Text(
                l10n.learningCenterTitle,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(l10n.learningOptionalDetail),
              const SizedBox(height: 16),
              Text(
                l10n.learningFocusTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final concept in learning.concepts)
                    Chip(label: Text(l10n.learningConceptName(concept))),
                ],
              ),
              if (controller.missionPrediction != null) ...[
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.psychology_alt_outlined),
                  title: Text(l10n.missionPredictionTitle),
                  subtitle: Text(
                    l10n.missionPredictionChoice(controller.missionPrediction!),
                  ),
                ),
              ],
              if (learning.has(MissionFeature.causalView) &&
                  controller.learningMode != LearningMode.starter)
                _CausalCard(controller: controller),
              if (learning.has(MissionFeature.experiment)) ...[
                const SizedBox(height: 8),
                _ExperimentCard(controller: controller),
              ],
              const SizedBox(height: 12),
              for (final concept in learning.concepts)
                _ConceptTile(
                  concept: concept,
                  technicalAvailable:
                      controller.learningMode != LearningMode.starter,
                  technicalExpanded:
                      controller.learningMode == LearningMode.explorer,
                ),
              if (learning.has(MissionFeature.challenges) &&
                  controller.learningMode == LearningMode.explorer &&
                  learning.challengeIds.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  l10n.challengesTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final challenge in learning.challengeIds)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.emoji_events_outlined),
                    title: Text(l10n.challengeName(challenge)),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ConceptTile extends StatelessWidget {
  const _ConceptTile({
    required this.concept,
    required this.technicalAvailable,
    required this.technicalExpanded,
  });

  final String concept;
  final bool technicalAvailable;
  final bool technicalExpanded;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.lightbulb_outline),
        title: Text(l10n.learningConceptName(concept)),
        subtitle: Text(l10n.actionLearnWhy),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Explanation(
            title: l10n.learningCauseTab,
            body: l10n.learningConceptCause(concept),
          ),
          if (technicalAvailable && !technicalExpanded)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text(l10n.learningMoreDetail),
              children: _technical(context, l10n),
            ),
          if (technicalExpanded) ..._technical(context, l10n),
        ],
      ),
    );
  }

  List<Widget> _technical(BuildContext context, AppLocalizations l10n) => [
    _Explanation(
      title: l10n.learningModelTab,
      body: l10n.learningConceptModel(concept),
    ),
    _Explanation(
      title: l10n.learningLawTab,
      body: l10n.learningConceptLaw(concept),
    ),
    TextButton.icon(
      onPressed: () async {
        final uri = Uri.parse(_modelDocsUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      icon: const Icon(Icons.open_in_new),
      label: Text(l10n.indicatorSourceLink),
    ),
  ];
}

class _Explanation extends StatelessWidget {
  const _Explanation({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 2),
        Text(body),
      ],
    ),
  );
}

class _CausalCard extends StatelessWidget {
  const _CausalCard({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final guidance = controller.goalGuidance;
    final name = guidance?.indicator == null
        ? l10n.goalMetricName(guidance?.metric ?? '')
        : l10n.indicatorName(guidance!.indicator!.name);
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.hub_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.causalViewTitle,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(l10n.causalPath(controller.level?.id ?? '')),
                  if (guidance != null)
                    Text(
                      l10n.causalNeedsAttention(name),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExperimentCard extends StatelessWidget {
  const _ExperimentCard({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final deltas = controller.experimentDeltas;
    final changed = deltas.values.where((value) => value.abs() >= 0.05).length;
    final locale = Localizations.localeOf(context).toString();
    final format = NumberFormat.decimalPatternDigits(
      locale: locale,
      decimalDigits: 1,
    );
    return Card(
      color: controller.experimentActive
          ? Theme.of(context).colorScheme.tertiaryContainer
          : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              controller.experimentActive
                  ? l10n.experimentActive
                  : l10n.experimentTitle,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(
              controller.experimentActive
                  ? (changed == 0
                        ? l10n.experimentNoChange
                        : l10n.experimentChanged(changed))
                  : l10n.experimentDescription,
            ),
            if (controller.experimentActive &&
                controller.learningMode == LearningMode.explorer)
              Wrap(
                spacing: 8,
                children: [
                  for (final entry in deltas.entries)
                    if (entry.value.abs() >= 0.05)
                      Chip(
                        label: Text(
                          '${l10n.indicatorName(entry.key.name)} '
                          '${entry.value >= 0 ? '+' : ''}${format.format(entry.value)}',
                        ),
                      ),
                ],
              ),
            const SizedBox(height: 8),
            if (!controller.experimentActive)
              FilledButton.tonalIcon(
                onPressed: controller.startExperiment,
                icon: const Icon(Icons.science_outlined),
                label: Text(l10n.actionStartExperiment),
              )
            else
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: controller.keepExperiment,
                    child: Text(l10n.actionKeepExperiment),
                  ),
                  OutlinedButton(
                    onPressed: controller.discardExperiment,
                    child: Text(l10n.actionDiscardExperiment),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
