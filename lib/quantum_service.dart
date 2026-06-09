import 'package:shared_preferences/shared_preferences.dart';
import 'puzzle_model.dart';

/// Persisted configuration for **Quantum Mode** — the tailor-your-session mode.
/// The player chooses which game types appear (drawn at random each board, only
/// from types they've unlocked), whether plain boards are mixed in, and whether
/// the session is timed. Remembered across launches so the setup screen
/// pre-fills their last choice.
///
/// Forward-looking: the picker is the natural premium surface — gate entry to it
/// behind a purchase flag here when monetization lands.
class QuantumService {
  static const _featKey   = 'quantum_features';
  static const _normalKey = 'quantum_normal';
  static const _timedKey  = 'quantum_timed';

  static Set<PuzzleFeature> features = {};   // chosen mechanic types
  static bool normal = true;                 // also include plain boards
  static bool timed  = false;                // timed session?
  static bool loaded = false;

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      normal = p.getBool(_normalKey) ?? true;
      timed  = p.getBool(_timedKey)  ?? false;
      final names = p.getStringList(_featKey);
      if (names != null) {
        features = names
            .map((n) => PuzzleFeature.values.where((f) => f.name == n))
            .expand((e) => e)
            .toSet();
      }
      loaded = true;
    } catch (_) {/* prefs unavailable — keep defaults */}
  }

  static Future<void> save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_normalKey, normal);
      await p.setBool(_timedKey, timed);
      await p.setStringList(_featKey, features.map((f) => f.name).toList());
    } catch (_) {/* best-effort persist */}
  }
}
