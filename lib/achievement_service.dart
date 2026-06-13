import 'dart:math';

import 'audio.dart';            // kMusicTracks — to resolve which tracks are unlocked
import 'daily_service.dart';
import 'field_guide.dart';
import 'progress_service.dart';
import 'stats_service.dart';

/// One achievement: completed when the merged stat [stat] reaches [target].
/// Achievements are **derived** from lifetime counters (no stored "claimed" flag) —
/// see [AchievementService.values].
class Achievement {
  final String id, name, desc, icon, stat;
  final int target;
  const Achievement(this.id, this.name, this.desc, this.icon, this.stat, this.target);
}

/// The canonical achievement list — the single source of truth shared by the
/// Achievements screen, the music-unlock gates, and the Penrose-skin unlock.
const List<Achievement> kAchievements = [
  Achievement('apprentice',    'Apprentice',           'Collapse 10 regions',               'worldline',  'solved',       10),
  Achievement('adept',         'Adept',                'Collapse 50 regions',               'worldline',  'solved',       50),
  Achievement('puzzle_master', 'Puzzle Master',        'Collapse 200 regions',              'blackhole',  'solved',       200),
  Achievement('grandmaster',   'Grandmaster',          'Collapse 500 regions',              'blackhole',  'solved',       500),
  Achievement('laplace',       'Laplace\'s Demon',     '50 flawless solves (no backtrack)', 'worldline',  'perfect',      50),
  Achievement('explorer',      'Explorer',             'Discover all five mechanics',       'objects',    'mechanics',    5),
  Achievement('parsecs',       'Less Than 12 Parsecs', 'Clear 25 wormhole regions',         'wormhole',   'wormhole',     25),
  Achievement('locksmith',     'Locksmith',            'Clear 25 mass-gate regions',        'gate',       'gate',         25),
  Achievement('slingshot',     'Slingshot',            'Clear 25 gravity-well regions',     'well',       'well',         25),
  Achievement('spooky',        'Spooky Action',        'Measure 25 entangled regions',      'entangled',  'entangled',    25),
  Achievement('many_worlds',   'Many Worlds',          'Traverse 25 multiverse regions',    'multiverse', 'multiverse',   25),
  Achievement('maxwell',       'Maxwell\'s Demon',     'Reach Entropy Lv 20',               'entropy',    'entropy',      20),
  // Entropy-ladder unlocks — earned by reaching Lv 16 on the tier below (the same
  // gate that opens the next difficulty). Event Horizon also unlocks the Penrose skin.
  Achievement('red_giant',     'Red Giant',            'Unlock Medium Entropy',             'entropy',    'easy_level',   16),
  Achievement('event_horizon', 'Event Horizon',        'Unlock Hard Entropy',               'blackhole',  'medium_level', 16),
  Achievement('dedicated',     'Dedicated',            'A 7-day daily streak',              'syntropy',   'streak',       7),
  Achievement('devoted',       'Devoted',              'A 30-day daily streak',             'syntropy',   'streak',       30),
];

/// Music tracks gated behind an achievement (**track id → required achievement id**).
/// Tracks not listed here are free from the start (currently just `bach_prelude`).
/// The in-game rotation pool is `enabled ∩ unlocked`; Settings shows the requirement.
const Map<String, String> kTrackUnlock = {
  'satie_gymnopedie': 'apprentice',     // Gymnopédie No. 1  — 10 solves
  'chopin_prelude_a': 'adept',          // Prelude in A      — 50 solves
  'bach_menuet':      'explorer',       // Menuet BWV 814    — all 5 mechanics
  'sugar_plum':       'red_giant',      // Sugar Plum Fairy  — unlock Medium
  'korobeiniki':      'grandmaster',    // Korobeiniki       — 500 solves
  'toccata_techno':   'event_horizon',  // Toccata · Techno  — unlock Hard
};

/// Computes which achievements (and thus music tracks / the Penrose skin) are
/// unlocked, from the persisted lifetime counters + per-difficulty progress.
class AchievementService {
  static const List<String> _mechanicSeen = [
    'seen_wormhole', 'seen_gate', 'seen_well', 'seen_entangled', 'seen_multiverse',
  ];

  /// The merged stat map every achievement is compared against. Mirrors the keys in
  /// [kAchievements] (`solved`, `perfect`, per-mechanic counts, `mechanics`,
  /// `entropy`, `easy_level`, `medium_level`, `streak`).
  static Future<Map<String, int>> values() async {
    final stats  = await StatsService.all();
    final seen   = await GuideService.seen();
    final easyLv = await ProgressService.bestLevel('easy');
    final medLv  = await ProgressService.bestLevel('medium');
    final hardLv = await ProgressService.bestLevel('hard');
    final streak = await DailyService.getMaxStreak();
    return {
      ...stats,
      'mechanics':    _mechanicSeen.where(seen.contains).length,
      'entropy':      max(easyLv, max(medLv, hardLv)),
      'easy_level':   easyLv,
      'medium_level': medLv,
      'streak':       streak,
    };
  }

  static bool isUnlocked(Achievement a, Map<String, int> values) =>
      (values[a.stat] ?? 0) >= a.target;

  /// Ids of every completed achievement.
  static Future<Set<String>> unlockedIds() async {
    final v = await values();
    return {for (final a in kAchievements) if (isUnlocked(a, v)) a.id};
  }

  /// Track ids the player may play = free tracks + those whose achievement is met.
  static Future<Set<String>> unlockedTracks() async {
    final ids = await unlockedIds();
    return {
      for (final t in kMusicTracks)
        if (!kTrackUnlock.containsKey(t.id) || ids.contains(kTrackUnlock[t.id])) t.id,
    };
  }
}
