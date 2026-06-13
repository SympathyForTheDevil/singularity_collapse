import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Monetization: the Premium entitlement + the free daily assist allowances.
///
/// **This is the testable scaffold — the ad and the IAP are STUBBED.** The gating
/// logic and the paywall UI are real; only *how the grants/entitlement get
/// triggered* is a placeholder:
///  - `setPremium(true)` is flipped by a dev toggle (Settings) now; later the real
///    `in_app_purchase` success callback flips it (+ restore-purchases).
///  - `grantAdHints()` / `grantAdSolution()` are called directly now; later a real
///    `google_mobile_ads` rewarded ad calls them on the reward callback.
/// When the SDKs land, only those trigger points change — the caps, the rollover,
/// and the paywall sheet stay as-is.
///
/// **Premium (one-time IAP) unlocks:** unlimited hints + solutions, no ads, and the
/// full Syntropy mechanic picker. (Penrose + music unlock *free* via achievements,
/// so they are deliberately NOT part of Premium.)
///
/// Free tier: [freeHintsPerDay] hints and [freeSolutionsPerDay] solutions per UTC
/// day; each rewarded ad tops up by [adHintGrant] / [adSolutionGrant]. Counters
/// reset on the UTC date rollover (matching the Daily puzzle's day).
class PremiumService {
  static const _kPremium   = 'premium';
  static const _kDay       = 'assist_day';
  static const _kHintsUsed = 'assist_hints_used';
  static const _kSolsUsed  = 'assist_sols_used';
  static const _kAdHints   = 'assist_ad_hints';
  static const _kAdSols    = 'assist_ad_sols';

  // Free allowances + ad top-up sizes (all // TUNE).
  static const int freeHintsPerDay     = 5;
  static const int freeSolutionsPerDay = 2;
  static const int adHintGrant         = 5;
  static const int adSolutionGrant     = 1;

  static bool premium = false;       // entitlement; loaded in main()
  static int _hintsUsed = 0, _solsUsed = 0, _adHints = 0, _adSols = 0;
  static String _day = '';

  static String _today() =>
      DateTime.now().toUtc().toIso8601String().substring(0, 10);

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    premium    = p.getBool(_kPremium) ?? false;
    _day       = p.getString(_kDay) ?? '';
    _hintsUsed = p.getInt(_kHintsUsed) ?? 0;
    _solsUsed  = p.getInt(_kSolsUsed) ?? 0;
    _adHints   = p.getInt(_kAdHints) ?? 0;
    _adSols    = p.getInt(_kAdSols) ?? 0;
    await _rollover(p);
  }

  /// Reset the daily counters when the UTC day changes.
  static Future<void> _rollover(SharedPreferences p) async {
    final t = _today();
    if (_day == t) return;
    _day = t;
    _hintsUsed = _solsUsed = _adHints = _adSols = 0;
    await p.setString(_kDay, _day);
    await p.setInt(_kHintsUsed, 0);
    await p.setInt(_kSolsUsed, 0);
    await p.setInt(_kAdHints, 0);
    await p.setInt(_kAdSols, 0);
  }

  // ── Allowances ──────────────────────────────────────────────────────────────
  static int get hintAllowance     => freeHintsPerDay + _adHints;
  static int get solutionAllowance => freeSolutionsPerDay + _adSols;
  /// Remaining today; -1 means unlimited (Premium).
  static int get hintsLeft     => premium ? -1 : max(0, hintAllowance - _hintsUsed);
  static int get solutionsLeft => premium ? -1 : max(0, solutionAllowance - _solsUsed);
  static bool get canHint     => premium || _hintsUsed < hintAllowance;
  static bool get canSolution => premium || _solsUsed < solutionAllowance;

  static Future<void> useHint() async {
    if (premium) return;
    final p = await SharedPreferences.getInstance();
    await _rollover(p);
    _hintsUsed++;
    await p.setInt(_kHintsUsed, _hintsUsed);
  }

  static Future<void> useSolution() async {
    if (premium) return;
    final p = await SharedPreferences.getInstance();
    await _rollover(p);
    _solsUsed++;
    await p.setInt(_kSolsUsed, _solsUsed);
  }

  // ── Rewarded-ad grants (STUB: called directly; real ad reward later) ─────────
  static Future<void> grantAdHints() async {
    final p = await SharedPreferences.getInstance();
    await _rollover(p);
    _adHints += adHintGrant;
    await p.setInt(_kAdHints, _adHints);
  }

  static Future<void> grantAdSolution() async {
    final p = await SharedPreferences.getInstance();
    await _rollover(p);
    _adSols += adSolutionGrant;
    await p.setInt(_kAdSols, _adSols);
  }

  // ── Entitlement (STUB: dev toggle; real in_app_purchase callback later) ──────
  static Future<void> setPremium(bool v) async {
    premium = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kPremium, v);
  }

  /// Dev/testing: clear today's assist usage + ad grants.
  static Future<void> resetDailyLimits() async {
    final p = await SharedPreferences.getInstance();
    _hintsUsed = _solsUsed = _adHints = _adSols = 0;
    await p.setInt(_kHintsUsed, 0);
    await p.setInt(_kSolsUsed, 0);
    await p.setInt(_kAdHints, 0);
    await p.setInt(_kAdSols, 0);
  }
}
