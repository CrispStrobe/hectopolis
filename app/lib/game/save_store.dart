// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:stadtbau_sim/stadtbau_sim.dart';

import 'experience_settings.dart';

/// A saved game: the level it belongs to (null = sandbox) and the world.
class SavedGame {
  const SavedGame({required this.levelId, required this.state});

  final String? levelId;
  final WorldState state;
}

/// Persists the current game and best level results locally
/// (shared_preferences: browser storage on web, platform preferences elsewhere).
class SaveStore {
  static const _autosaveKey = 'stadtbau.autosave.v2';
  static const _starsKey = 'stadtbau.stars.v1';
  static const _onboardingKey = 'stadtbau.onboarding.v1';
  static const _experienceKey = 'stadtbau.experience.v1';

  Future<void> save(String? levelId, Simulation sim) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _autosaveKey,
      jsonEncode({'levelId': levelId, 'state': sim.state.toJson()}),
    );
  }

  Future<SavedGame?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_autosaveKey);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return SavedGame(
        levelId: json['levelId'] as String?,
        state: WorldState.fromJson(json['state'] as Map<String, dynamic>),
      );
    } on Object {
      await prefs.remove(_autosaveKey);
      return null;
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_autosaveKey);
  }

  /// Whether the three-step onboarding overlay has already been shown (T-208).
  Future<bool> onboardingSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_onboardingKey) ?? false;
  }

  Future<void> markOnboardingSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingKey, true);
  }

  Future<ExperienceSettings> loadExperienceSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_experienceKey);
    if (raw == null) return const ExperienceSettings();
    try {
      return ExperienceSettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } on Object {
      await prefs.remove(_experienceKey);
      return const ExperienceSettings();
    }
  }

  Future<void> saveExperienceSettings(ExperienceSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_experienceKey, jsonEncode(settings.toJson()));
  }

  Future<Map<String, int>> bestStars() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_starsKey);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, (v as num).toInt()),
      );
    } on Object {
      return {};
    }
  }

  Future<void> recordStars(String levelId, int stars) async {
    final best = await bestStars();
    if ((best[levelId] ?? 0) >= stars) return;
    best[levelId] = stars;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_starsKey, jsonEncode(best));
  }
}
