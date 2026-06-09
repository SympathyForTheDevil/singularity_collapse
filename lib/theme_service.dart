import 'package:shared_preferences/shared_preferences.dart';

/// Cosmetic board themes. The **Penrose** ("spacetime diagram") theme tilts the
/// whole board 45° into a diamond, so the orthogonal step directions line up
/// with a Penrose diagram's 45° light cones and the worldline reads as a literal
/// null-ray path toward the singularity. Purely visual — the puzzle, generation,
/// and rules are untouched; only rendering and input-hit-testing are rotated.
///
/// Persisted like the mute flag. Kept as a static singleton so the home screen,
/// the puzzle screen, and its painter can all read it without threading it
/// through constructors. Forward-looking: this is the hook an "unlockable perk"
/// would gate (set it from wherever the unlock/purchase lands).
class ThemeService {
  static const _penroseKey = 'penrose_theme';

  /// Whether the 45° Penrose/spacetime board skin is active.
  static bool penrose = false;

  /// Load persisted theme prefs. Call once at startup (fails silently).
  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      penrose = p.getBool(_penroseKey) ?? false;
    } catch (_) {/* prefs unavailable — keep defaults */}
  }

  static Future<void> setPenrose(bool value) async {
    penrose = value;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_penroseKey, value);
    } catch (_) {/* best-effort persist */}
  }
}
