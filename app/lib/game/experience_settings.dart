// SPDX-License-Identifier: AGPL-3.0-or-later

/// Player-controlled presentation settings. They deliberately do not affect
/// simulation results, saves, or level scoring.
class ExperienceSettings {
  const ExperienceSettings({
    this.simpleMode = false,
    this.cleanVisuals = false,
    this.ambientAnimations = true,
    this.trafficAnimations = true,
    this.environmentAnimations = true,
    this.cityActivityAnimations = true,
    this.effectAnimations = true,
    this.placementForecasts = true,
    this.causalHighlights = true,
    this.soundEffects = false,
    this.haptics = true,
  });

  final bool simpleMode;
  final bool cleanVisuals;
  final bool ambientAnimations;
  final bool trafficAnimations;
  final bool environmentAnimations;
  final bool cityActivityAnimations;
  final bool effectAnimations;
  final bool placementForecasts;
  final bool causalHighlights;
  final bool soundEffects;
  final bool haptics;

  ExperienceSettings copyWith({
    bool? simpleMode,
    bool? cleanVisuals,
    bool? ambientAnimations,
    bool? trafficAnimations,
    bool? environmentAnimations,
    bool? cityActivityAnimations,
    bool? effectAnimations,
    bool? placementForecasts,
    bool? causalHighlights,
    bool? soundEffects,
    bool? haptics,
  }) => ExperienceSettings(
    simpleMode: simpleMode ?? this.simpleMode,
    cleanVisuals: cleanVisuals ?? this.cleanVisuals,
    ambientAnimations: ambientAnimations ?? this.ambientAnimations,
    trafficAnimations: trafficAnimations ?? this.trafficAnimations,
    environmentAnimations: environmentAnimations ?? this.environmentAnimations,
    cityActivityAnimations:
        cityActivityAnimations ?? this.cityActivityAnimations,
    effectAnimations: effectAnimations ?? this.effectAnimations,
    placementForecasts: placementForecasts ?? this.placementForecasts,
    causalHighlights: causalHighlights ?? this.causalHighlights,
    soundEffects: soundEffects ?? this.soundEffects,
    haptics: haptics ?? this.haptics,
  );

  factory ExperienceSettings.fromJson(Map<String, dynamic> json) =>
      ExperienceSettings(
        simpleMode: json['simpleMode'] as bool? ?? false,
        cleanVisuals: json['cleanVisuals'] as bool? ?? false,
        ambientAnimations: json['ambientAnimations'] as bool? ?? true,
        trafficAnimations: json['trafficAnimations'] as bool? ?? true,
        environmentAnimations: json['environmentAnimations'] as bool? ?? true,
        cityActivityAnimations: json['cityActivityAnimations'] as bool? ?? true,
        effectAnimations: json['effectAnimations'] as bool? ?? true,
        placementForecasts: json['placementForecasts'] as bool? ?? true,
        causalHighlights: json['causalHighlights'] as bool? ?? true,
        soundEffects: json['soundEffects'] as bool? ?? false,
        haptics: json['haptics'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
    'simpleMode': simpleMode,
    'cleanVisuals': cleanVisuals,
    'ambientAnimations': ambientAnimations,
    'trafficAnimations': trafficAnimations,
    'environmentAnimations': environmentAnimations,
    'cityActivityAnimations': cityActivityAnimations,
    'effectAnimations': effectAnimations,
    'placementForecasts': placementForecasts,
    'causalHighlights': causalHighlights,
    'soundEffects': soundEffects,
    'haptics': haptics,
  };
}
