import 'package:shared_preferences/shared_preferences.dart';

/// Result of recording a daily solve.
typedef SolveResult = ({int streak, int freezes, bool freezeUsed, bool freezeEarned});

class DailyService {
  static const _keyLastSolved = 'last_solved_date';
  static const _keyStreak     = 'streak';
  static const _keyMaxStreak  = 'max_streak';
  static const _keyFreezes    = 'streak_freezes';

  /// A streak freeze covers one missed day, protecting the streak. You earn one
  /// every 7 consecutive days, holding at most [maxFreezes].
  static const int maxFreezes = 2;

  static String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime _today() => DateTime.now().toUtc();

  static String todayStr() => _fmt(_today());

  /// Integer seed stable for the UTC calendar day — same day → same puzzle for everyone.
  static int todaySeed() {
    final n = _today();
    return n.year * 10000 + n.month * 100 + n.day;
  }

  /// Difficulty ramps from day 1 (5×5) and plateaus at 8×8 around day 9.
  static int dailyLevel() {
    final epoch = DateTime.utc(2026, 6, 8);
    final days  = _today().difference(epoch).inDays;
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

  static Future<int> getFreezes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyFreezes) ?? 0;
  }

  static Future<int> getMaxStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyMaxStreak) ?? 0;
  }

  static Future<String?> getLastSolved() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastSolved);
  }

  /// Marks today solved and updates the streak + freeze tokens:
  ///  • consecutive day → streak +1;
  ///  • missed days, covered by available freezes (1 freeze per missed day) →
  ///    consume them and keep the streak alive;
  ///  • otherwise → streak resets to 1.
  /// A freeze is earned every 7 consecutive days (held up to [maxFreezes]).
  static Future<SolveResult> markSolvedAndGetStreak() async {
    final prefs = await SharedPreferences.getInstance();
    final today = todayStr();
    var freezes = prefs.getInt(_keyFreezes) ?? 0;
    final prev  = prefs.getInt(_keyStreak) ?? 0;
    final last  = prefs.getString(_keyLastSolved);

    if (last == today) {
      return (streak: prev < 1 ? 1 : prev, freezes: freezes,
              freezeUsed: false, freezeEarned: false);
    }

    // Whole missed days between the last solve and today (0 if last == yesterday).
    var missed = 0;
    if (last != null) {
      final p = last.split('-').map(int.parse).toList();
      final lastUtc  = DateTime.utc(p[0], p[1], p[2]);
      final n        = _today();
      final todayUtc = DateTime.utc(n.year, n.month, n.day);
      missed = todayUtc.difference(lastUtc).inDays - 1;
    }

    var freezeUsed = false;
    final int streak;
    if (last == null || prev == 0) {
      streak = 1;
    } else if (missed <= 0) {
      streak = prev + 1;
    } else if (missed <= freezes) {
      freezes -= missed;                 // freeze(s) bridge the gap
      freezeUsed = true;
      streak = prev + 1;
    } else {
      streak = 1;                        // too many missed days — streak breaks
    }

    // Earn a freeze every 7 consecutive days, capped.
    var freezeEarned = false;
    if (streak % 7 == 0 && freezes < maxFreezes) {
      freezes += 1;
      freezeEarned = true;
    }

    await prefs.setString(_keyLastSolved, today);
    await prefs.setInt(_keyStreak, streak);
    await prefs.setInt(_keyFreezes, freezes);
    if (streak > (prefs.getInt(_keyMaxStreak) ?? 0)) {
      await prefs.setInt(_keyMaxStreak, streak);
    }
    return (streak: streak, freezes: freezes,
            freezeUsed: freezeUsed, freezeEarned: freezeEarned);
  }
}
