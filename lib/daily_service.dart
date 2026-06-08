import 'package:shared_preferences/shared_preferences.dart';

class DailyService {
  static const _keyLastSolved = 'last_solved_date';
  static const _keyStreak     = 'streak';

  static String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String todayStr() => _fmt(DateTime.now());

  /// Integer seed stable for the calendar day — same day → same puzzle for everyone.
  static int todaySeed() {
    final n = DateTime.now();
    return n.year * 10000 + n.month * 100 + n.day;
  }

  /// Difficulty ramps from day 1 (5×5) and plateaus at 8×8 around day 9.
  static int dailyLevel() {
    final epoch = DateTime(2026, 6, 8);
    final days  = DateTime.now().difference(epoch).inDays;
    return (days + 1).clamp(1, 15);
  }

  static Future<bool> isSolvedToday() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastSolved) == todayStr();
  }

  static Future<int> getStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyStreak) ?? 0;
  }

  /// Marks today solved, updates streak, returns new streak value.
  static Future<int> markSolvedAndGetStreak() async {
    final prefs     = await SharedPreferences.getInstance();
    final today     = todayStr();
    final last      = prefs.getString(_keyLastSolved);
    if (last == today) return prefs.getInt(_keyStreak) ?? 1;

    final yesterday = _fmt(DateTime.now().subtract(const Duration(days: 1)));
    final prev      = prefs.getInt(_keyStreak) ?? 0;
    final streak    = (last == yesterday) ? prev + 1 : 1;
    await prefs.setString(_keyLastSolved, today);
    await prefs.setInt(_keyStreak, streak);
    return streak;
  }
}
