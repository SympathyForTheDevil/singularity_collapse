import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-day daily-puzzle results, stored as { 'YYYY-MM-DD': badgeMask }. Each solve
/// earns a set of collectible achievement badges (a bitmask), not a single tier.
class ProgressService {
  static const _key = 'daily_badges';

  // ── Achievement badges (bit flags) ─────────────────────────────────────────
  static const int perfect = 1;   // no backtracks
  static const int unaided = 2;   // never revealed the solution
  static const int swift   = 4;   // solved under par
  static const int blazing = 8;   // solved under half par

  /// Display order.
  static const List<int> order = [perfect, unaided, swift, blazing];

  static String nameOf(int flag) => switch (flag) {
    perfect => 'PERFECT',
    unaided => 'UNAIDED',
    swift   => 'SWIFT',
    _       => 'BLAZING',
  };
  static String noteOf(int flag) => switch (flag) {
    perfect => 'NO BACKTRACKS',
    unaided => 'NO PEEK',
    swift   => 'UNDER PAR',
    _       => 'HALF PAR',
  };

  /// Par time (seconds) for a board of [cells]; under it earns SWIFT. Gentle and
  /// board-scaled so the speed badges stay earnable on big boards. Tune by playtest.
  static int parSeconds(int cells) => (cells * 1.7).round();

  /// The badge bitmask earned for a solve.
  static int badgesFor({
    required bool backtracked,
    required bool peeked,
    required int seconds,
    required int parSec,
  }) {
    var b = 0;
    if (!backtracked)                  b |= perfect;
    if (!peeked)                       b |= unaided;
    if (seconds <= parSec)             b |= swift;
    if (seconds <= (parSec / 2).round()) b |= blazing;
    return b;
  }

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

  /// Record [badges] for [date], OR-ing with anything already earned that day.
  static Future<void> record(String date, int badges) async {
    final p = await SharedPreferences.getInstance();
    final m = await all();
    final merged = (m[date] ?? 0) | badges;
    if (merged == (m[date] ?? -1)) return;
    m[date] = merged;
    await p.setString(_key, jsonEncode(m));
  }
}
