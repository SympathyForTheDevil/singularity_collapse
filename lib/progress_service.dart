import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-day daily-puzzle results, for medals + the star-map. Stored as a single
/// JSON map { 'YYYY-MM-DD': medal } where medal is 1=Bronze, 2=Silver, 3=Gold
/// (0 = unsolved). Only the *best* medal for a day is kept.
class ProgressService {
  static const _key = 'daily_medals';

  // Medal tiers.
  static const int none = 0, bronze = 1, silver = 2, gold = 3;
  static const List<String> medalName = ['—', 'BRONZE', 'SILVER', 'GOLD'];
  static const List<String> medalNote =
      ['', 'SOLVED', 'UNDER PAR', 'FLAWLESS · NO BACKTRACKS'];

  /// Par time (seconds) for a board of [cells] — under it earns at least Silver.
  /// A gentle, beatable target; tune with playtest.
  static int parSeconds(int cells) => (cells * 1.7).round();

  /// The medal earned for a solve: Gold for a clean (no-backtrack) solve, else
  /// Silver if under par, else Bronze.
  static int medalFor({required bool backtracked, required int seconds, required int parSec}) =>
      !backtracked ? gold : (seconds <= parSec ? silver : bronze);

  static Future<Map<String, int>> all() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_key);
    if (s == null) return {};
    try {
      final m = jsonDecode(s) as Map<String, dynamic>;
      return m.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  /// Record [medal] for [date], keeping the best result for that day.
  static Future<void> record(String date, int medal) async {
    final p = await SharedPreferences.getInstance();
    final m = await all();
    if ((m[date] ?? 0) >= medal) return;
    m[date] = medal;
    await p.setString(_key, jsonEncode(m));
  }
}
