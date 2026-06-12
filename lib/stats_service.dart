import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Lifetime gameplay counters that drive **achievements**. Stored as one JSON map
/// `{ statKey: count }`, bumped once per region collapsed (PuzzleScreen._onSolved).
class StatsService {
  static const _key = 'lifetime_stats';

  // Stat keys.
  static const solved     = 'solved';      // total regions collapsed (all modes)
  static const perfect    = 'perfect';     // solved with no backtrack
  static const wormhole   = 'wormhole';    // solved a board containing this mechanic
  static const gate       = 'gate';
  static const well       = 'well';
  static const entangled  = 'entangled';
  static const multiverse = 'multiverse';

  static Future<Map<String, int>> all() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_key);
    if (s == null) return {};
    try {
      return (jsonDecode(s) as Map)
          .map((k, v) => MapEntry(k as String, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  /// Add [deltas] to the stored counters (one write per solve). Fire-and-forget.
  static Future<void> bump(Map<String, int> deltas) async {
    if (deltas.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    final m = await all();
    deltas.forEach((k, v) => m[k] = (m[k] ?? 0) + v);
    await p.setString(_key, jsonEncode(m));
  }
}
