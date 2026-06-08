import 'dart:collection';
import 'dart:math';

/// Accretion Cascade — a score-attack "run" mode. Drag one continuous worldline
/// over a board of cosmic objects, absorbing them to build a score, and reach
/// the Black Hole to "collapse" and bank it. Separate from the Classic puzzle:
/// no fill-every-cell, no ordering, no solvable-by-construction generation.
///
/// This prototype is an *experiment harness*: the cascade core and the risk
/// model are both switchable at runtime ([AccretionConfig]) so every
/// combination can be playtested from a single build.

enum CascadeCore { fusion, ladder, collect }
enum RiskModel   { darkMatter, shrink, stepBudget }
enum RunStatus   { playing, banked, busted }

class AccretionConfig {
  final CascadeCore core;
  final RiskModel   risk;
  const AccretionConfig({this.core = CascadeCore.fusion, this.risk = RiskModel.darkMatter});
  AccretionConfig copyWith({CascadeCore? core, RiskModel? risk}) =>
      AccretionConfig(core: core ?? this.core, risk: risk ?? this.risk);

  static String coreLabel(CascadeCore c) => switch (c) {
    CascadeCore.fusion  => 'FUSION',
    CascadeCore.ladder  => 'LADDER',
    CascadeCore.collect => 'SET',
  };
  static String riskLabel(RiskModel r) => switch (r) {
    RiskModel.darkMatter => 'DARK MATTER',
    RiskModel.shrink     => 'SHRINK',
    RiskModel.stepBudget => 'STEP BUDGET',
  };
}

/// What happened on a single [AccretionGame.step], so the screen can fire the
/// right audio / animations.
class StepResult {
  final bool moved;
  final bool absorbed;
  final List<int> fusions;  // resulting tiers of fusions/pops (for pitched audio)
  final bool banked;        // reached the Black Hole → safe cash-out
  final bool busted;        // run ended early (trapped / out of budget)
  const StepResult({
    this.moved = false, this.absorbed = false, this.fusions = const [],
    this.banked = false, this.busted = false,
  });
  static const none = StepResult();
  bool get ended => banked || busted;
}

class AccretionGame {
  // Cell codes (>=1 are cosmic-object tiers 1..maxTier).
  static const int kVoid      = 0;
  static const int kDark      = -1;
  static const int kBlackHole = -2;

  static const int maxTier   = 6;   // top fusion product (Neutron Star)
  static const int fuseCount = 3;   // fusion core: N of a tier → next tier
  static const int setCount  = 4;   // collect core: N of a tier → pop
  static const int baseSteps = 42;  // step-budget allowance

  AccretionConfig config;
  final int size;
  late List<int> cells;       // per-cell code
  final List<int> path = [];  // visited cell indices (in order)

  int       mass       = 0;
  double    multiplier = 1.0;
  RunStatus status     = RunStatus.playing;
  int       finalScore = 0;

  int stepsLeft = baseSteps;          // stepBudget
  final Set<int> dark = <int>{};      // darkMatter spread

  // core-private accumulators
  final Map<int, int> _pending = {};  // fusion / collect tallies
  int _lastTier = 0;                  // ladder
  int _combo    = 0;                  // ladder

  final Random _rng;

  AccretionGame(this.config, {int? seed, this.size = 7})
      : _rng = Random(seed) {
    _generate();
  }

  int get cellCount     => size * size;
  int rowOf(int i)      => i ~/ size;
  int colOf(int i)      => i % size;
  int get head          => path.isEmpty ? -1 : path.last;
  int get blackHoleCell => cells.indexOf(kBlackHole);
  int get projectedScore => (mass * multiplier).round();

  bool isObject(int code) => code >= 1;
  int  tierAt(int i)      => cells[i];

  static int tierValue(int t) =>
      const [0, 1, 3, 9, 27, 81, 243][t < 0 ? 0 : (t > 6 ? 6 : t)];

  // ── Generation ──────────────────────────────────────────────────────────
  void reset({AccretionConfig? config}) {
    if (config != null) this.config = config;
    path.clear();
    mass = 0; multiplier = 1.0; status = RunStatus.playing; finalScore = 0;
    stepsLeft = baseSteps;
    dark.clear();
    _pending.clear(); _lastTier = 0; _combo = 0;
    _generate();
  }

  void _generate() {
    cells = List<int>.filled(cellCount, kVoid);
    // Weighted spawn: low tiers common, voids rare. Fusion creates 5/6.
    for (var i = 0; i < cellCount; i++) {
      final r = _rng.nextDouble();
      cells[i] = r < 0.05 ? kVoid
               : r < 0.40 ? 1
               : r < 0.68 ? 2
               : r < 0.86 ? 3
               :            4;
    }
    // Black Hole somewhere in the interior-ish.
    cells[_rng.nextInt(cellCount)] = kBlackHole;

    if (config.risk == RiskModel.darkMatter) {
      // Seed a couple of corners so the spread has somewhere to grow from.
      final corners = [0, size - 1, cellCount - size, cellCount - 1]..shuffle(_rng);
      for (final c in corners.take(2)) {
        if (cells[c] != kBlackHole) { cells[c] = kDark; dark.add(c); }
      }
    }
  }

  // ── Stepping ──────────────────────────────────────────────────────────────
  List<int> neighbors(int i) {
    final r = rowOf(i), c = colOf(i);
    return [
      if (r > 0)        i - size,
      if (r < size - 1) i + size,
      if (c > 0)        i - 1,
      if (c < size - 1) i + 1,
    ];
  }

  bool adjacent(int a, int b) =>
      (rowOf(a) - rowOf(b)).abs() + (colOf(a) - colOf(b)).abs() == 1;

  /// A cell is steppable if it's an object or the Black Hole, unvisited, and
  /// (for the first step) any valid cell; otherwise adjacent to the head.
  bool canStep(int target) {
    if (status != RunStatus.playing) return false;
    if (target < 0 || target >= cellCount) return false;
    if (path.contains(target)) return false;
    final code = cells[target];
    if (code == kVoid || code == kDark) return false;
    if (path.isEmpty) return code != kBlackHole; // don't start on the finish
    return adjacent(head, target);
  }

  bool _trapped() => !neighbors(head).any(canStep);

  StepResult step(int target) {
    if (!canStep(target)) return StepResult.none;
    path.add(target);

    if (cells[target] == kBlackHole) {
      _bank(true);
      return const StepResult(moved: true, banked: true);
    }

    final tier = cells[target];
    mass += tierValue(tier);
    final fusions = switch (config.core) {
      CascadeCore.fusion  => _absorbFusion(tier),
      CascadeCore.ladder  => _absorbLadder(tier),
      CascadeCore.collect => _absorbCollect(tier),
    };

    // Per-step risk.
    var busted = false;
    switch (config.risk) {
      case RiskModel.stepBudget:
        if (--stepsLeft <= 0) busted = true;
      case RiskModel.darkMatter:
        _spreadDark();
        if (_trapped()) busted = true;
      case RiskModel.shrink:
        if (!_blackHoleReachable() || _trapped()) busted = true;
    }
    if (busted) {
      _bank(false);
      return StepResult(moved: true, absorbed: true, fusions: fusions, busted: true);
    }
    return StepResult(moved: true, absorbed: true, fusions: fusions);
  }

  void _bank(bool success) {
    status = success ? RunStatus.banked : RunStatus.busted;
    // Cash-out banks mass × multiplier. Bust loses the multiplier (×1), except
    // SHRINK where stranding yourself scores nothing.
    finalScore = success
        ? projectedScore
        : (config.risk == RiskModel.shrink ? 0 : mass);
  }

  // ── Cascade cores ──────────────────────────────────────────────────────────
  List<int> _absorbFusion(int tier) {
    final out = <int>[];
    _pending[tier] = (_pending[tier] ?? 0) + 1;
    var t = tier;
    while (t < maxTier && (_pending[t] ?? 0) >= fuseCount) {
      _pending[t] = _pending[t]! - fuseCount;
      t += 1;
      _pending[t] = (_pending[t] ?? 0) + 1;
      mass += tierValue(t);     // fusion bonus
      multiplier += 0.3;
      out.add(t);
    }
    return out;
  }

  List<int> _absorbLadder(int tier) {
    if (tier > _lastTier) {
      _combo += 1;
      multiplier = 1 + 0.5 * _combo;
    } else {
      _combo = 0;
      multiplier = 1.0;
    }
    _lastTier = tier;
    return const [];
  }

  List<int> _absorbCollect(int tier) {
    _pending[tier] = (_pending[tier] ?? 0) + 1;
    if (_pending[tier]! >= setCount) {
      _pending[tier] = _pending[tier]! - setCount;
      mass += tierValue(tier) * setCount;  // pop bonus
      multiplier += 0.5;
      return [tier];
    }
    return const [];
  }

  // ── Risk helpers ────────────────────────────────────────────────────────────
  void _spreadDark() {
    const rate = 2;
    // Prefer growing from existing dark for an organic creep.
    final candidates = <int>{};
    for (final d in dark) {
      for (final nb in neighbors(d)) {
        if (isObject(cells[nb]) && !path.contains(nb)) candidates.add(nb);
      }
    }
    if (candidates.isEmpty) {
      for (var i = 0; i < cellCount; i++) {
        if (isObject(cells[i]) && !path.contains(i)) candidates.add(i);
      }
    }
    final list = candidates.toList()..shuffle(_rng);
    for (final c in list.take(rate)) { cells[c] = kDark; dark.add(c); }
  }

  /// BFS from the head over unvisited object/Black-Hole cells (shrink mode).
  bool _blackHoleReachable() {
    final bh = blackHoleCell;
    if (bh < 0) return false;
    final seen = List<bool>.filled(cellCount, false);
    final q = Queue<int>()..add(head);
    seen[head] = true;
    while (q.isNotEmpty) {
      final cur = q.removeFirst();
      for (final nb in neighbors(cur)) {
        if (seen[nb] || path.contains(nb)) continue;
        final code = cells[nb];
        if (code == kVoid || code == kDark) continue;
        if (nb == bh) return true;
        seen[nb] = true;
        q.add(nb);
      }
    }
    return false;
  }
}
