import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'audio.dart';
import 'cosmic.dart';
import 'daily_service.dart';
import 'field_guide.dart';
import 'progress_service.dart';
import 'puzzle_model.dart';
import 'theme_service.dart';

enum PuzzleMode { daily, entropy, quantum }

/// Entropy-run difficulty — scales how fast entropy fills and the score reward.
enum RunDifficulty { easy, medium, hard }

/// Singularity: Collapse — the standalone puzzle. Drag one worldline that
/// consumes cosmic objects in ascending order and fills every cell; reaching
/// the Black Hole (the final cell) collapses the region into a larger one.
class PuzzleScreen extends StatefulWidget {
  final PuzzleMode mode;
  /// Difficulty for the Entropy run (ignored by other modes).
  final RunDifficulty difficulty;
  /// Dev/test overrides: force a specific feature set and a fixed level.
  final Set<PuzzleFeature>? forceFeatures;
  final int? fixedLevel;
  /// Dev override: number of stacked boards when forcing multiverse (2 or 3).
  final int? multiverseBoards;
  /// Quantum mode config: the mechanic types the player chose to see (drawn from
  /// at random each board), whether to also include plain boards, and timed-or-not.
  final Set<PuzzleFeature> quantumFeatures;
  final bool quantumNormal;
  final bool quantumTimed;
  const PuzzleScreen({
    super.key,
    this.mode = PuzzleMode.entropy,
    this.difficulty = RunDifficulty.medium,
    this.forceFeatures,
    this.fixedLevel,
    this.multiverseBoards,
    this.quantumFeatures = const {},
    this.quantumNormal = true,
    this.quantumTimed = false,
  });
  @override
  State<PuzzleScreen> createState() => _PuzzleScreenState();
}

/// Gap (px) between stacked boards in the multiverse layout.
const double _kBoardGap = 18;

/// Where each board of a (possibly multi-board) puzzle sits inside the board
/// area, and how big its cells are. Boards stack vertically (rows × cols, square
/// cells), cell size maximised to fit the area; the group is centred. Shared by
/// the painter (render) and the screen (input hit-testing) so they never drift.
class _BoardLayout {
  final double cell;
  final List<Offset> origins;   // top-left of each board (length boardCount)
  final int rows;               // per-board grid height (cells)
  final int cols;               // per-board grid width  (cells)
  final int na;                 // rows * cols
  const _BoardLayout(this.cell, this.origins, this.rows, this.cols, this.na);

  double get boardW => cols * cell;
  double get boardH => rows * cell;

  static _BoardLayout of(Size area, int boardCount, int rows, int cols) {
    final cell = min(
      area.width / cols,
      (area.height - _kBoardGap * (boardCount - 1)) / boardCount / rows,
    );
    final boardW = cols * cell, boardH = rows * cell;
    final totalH = boardH * boardCount + _kBoardGap * (boardCount - 1);
    final top  = (area.height - totalH) / 2;
    final left = (area.width  - boardW) / 2;
    return _BoardLayout(cell, [
      for (var b = 0; b < boardCount; b++)
        Offset(left, top + b * (boardH + _kBoardGap)),
    ], rows, cols, rows * cols);
  }

  Offset center(int g) {
    final o = origins[g ~/ na], li = g % na;
    return Offset(o.dx + (li % cols + 0.5) * cell,
                  o.dy + (li ~/ cols + 0.5) * cell);
  }

  int? cellAt(Offset p) {
    for (var b = 0; b < origins.length; b++) {
      final lx = p.dx - origins[b].dx, ly = p.dy - origins[b].dy;
      if (lx < 0 || ly < 0 || lx >= boardW || ly >= boardH) continue;
      final c = (lx / cell).floor().clamp(0, cols - 1);
      final r = (ly / cell).floor().clamp(0, rows - 1);
      return b * na + r * cols + c;
    }
    return null;
  }

  /// Fraction (0..1 each axis) of where [p] falls within cell [g], or null if
  /// [p] isn't on that cell's board. Used by the undo deep-inside gate.
  Offset? fracInCell(Offset p, int g) {
    final o = origins[g ~/ na], li = g % na;
    return Offset((p.dx - o.dx - (li % cols) * cell) / cell,
                  (p.dy - o.dy - (li ~/ cols) * cell) / cell);
  }
}

class _PuzzleScreenState extends State<PuzzleScreen>
    with TickerProviderStateMixin {
  late PuzzleGrid grid;
  final List<int> path = [];
  int  level       = 1;
  int  solvedCount = 0;
  bool solved      = false;
  bool _showShare  = false;
  bool _backtracked = false;   // any undo/reset this solve → forfeits PERFECT
  bool _peeked      = false;   // revealed the solution this solve → forfeits UNAIDED
  int  _lastBadges  = 0;       // achievement badges earned on the just-finished daily
  bool _freezeUsed  = false;   // a streak freeze saved the streak this solve
  bool _freezeEarned = false;  // earned a freeze this solve (7-day milestone)
  bool _paused     = false;
  bool _muted      = AudioService.instance.muted;
  final bool _penrose = ThemeService.penrose;  // 45° spacetime-diagram board skin
  int  _streak     = 0;

  // Timer
  int    _seconds = 0;
  Timer? _timer;

  late final AnimationController _pulse;
  late final AnimationController _solve;
  late final AnimationController _nudge;   // black-hole "not yet" warning flash
  late final AnimationController _warp;    // wormhole teleport flash
  late final AnimationController _unlock;  // mass-gate open ripple
  late final AnimationController _sling;   // gravity-well launch streak
  late final AnimationController _trace;   // solution-reveal tracer sweep
  late final AnimationController _measure; // entangled collapse flash

  // First-encounter teaching cards. A mechanic is taught once, ever.
  final Set<String> _seenKeys = {};        // persisted "encountered" flags
  bool _seenLoaded = false;
  final List<GuideEntry> _cards = [];       // queued tutorial cards (front = active)
  bool _showSolution = false;              // reveal the full answer (playtest / premium)
  List<int> _hintCells = const [];         // a few next-step hint cells (premium hook)
  Timer? _hintCellsTimer;
  static const int _hintSteps = 3;         // how many next cells a hint reveals

  // Atomic moves (a gravity-well launch or a wormhole teleport) span several
  // cells but undo/rewind as one unit. Maps the path index of the move's first
  // cell → the number of cells it added.
  final Map<int, int> _atomic = {};
  int? _slingFrom, _slingTo;               // cells the current launch streaks between

  // Transient in-context hint shown in the NEXT line (e.g. why a move was blocked).
  String?  _hint;
  Timer?   _hintTimer;
  int      _lastNudgeMs = 0;               // throttle the nudge
  int      _nudgeKind   = 0;               // 0 none · 1 black hole · 2 mass gate

  double _boardSize = 320;
  _BoardLayout? _layout;   // board placement (multi-board aware), set each build

  static const Color _accent = Color(0xffffc24d);

  bool get _isDaily    => widget.mode == PuzzleMode.daily;
  bool get _isQuantum  => widget.mode == PuzzleMode.quantum;
  bool get _isEntropy => widget.mode == PuzzleMode.entropy;

  // ── Entropy run (high-score survival) ───────────────────────────────────────
  double _entropy   = 0;     // 0..1; rises while solving + on mistakes, run-wide
  int    _runScore  = 0;     // accrues per board solved this run
  int    _bestScore = 0;     // best run at this difficulty (loaded on game over)
  bool   _runOver   = false; // entropy hit 1.0 → run ended
  static const double _kEntBacktrack = 0.04;  // TUNE — entropy per backtrack
  static const double _kEntHint      = 0.06;  // TUNE — per hint
  static const double _kEntSolution  = 0.25;  // TUNE — per solution peek
  static const double _kEntVent      = 0.28;  // TUNE — relief on solving a board
  static const double _kEntStep      = 0.05;  // TUNE — entropy added per tick

  /// Seconds between passive entropy ticks — gentler on Easy, harsher on Hard,
  /// and tightening with depth. Medium ≈ every 9s early (per the "8–10" target).
  int _entropyTick() {
    final base = switch (widget.difficulty) {
      RunDifficulty.easy   => 12,
      RunDifficulty.medium => 9,
      RunDifficulty.hard   => 6,
    };
    return (base - level ~/ 4).clamp(3, base);   // TUNE — speeds up as you go deep
  }

  /// Score reward multiplier per difficulty.
  double _scoreMult() => switch (widget.difficulty) {
    RunDifficulty.easy => 1.0, RunDifficulty.medium => 1.3, RunDifficulty.hard => 1.7,
  };

  void _addEntropy(double d) {
    if (!_isEntropy || _runOver) return;
    _entropy = (_entropy + d).clamp(0.0, 1.0);   // game-over is checked in the timer
  }
  /// Whether the timer is shown/relevant: always in Daily/Infinity; in Quantum
  /// only when the player chose a timed session.
  bool get _timed => !_isQuantum || widget.quantumTimed;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
    _nudge = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600));
    _warp = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 520))
      // Flash up on teleport, then fade back to the idle portal look.
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _warp.reverse();
      });
    _unlock = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600));
    _sling = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 320));
    _trace = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2600));
    _measure = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 650));
    _solve = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2000))
      ..addStatusListener((s) async {
        if (s == AnimationStatus.completed && mounted) {
          if (_isDaily) {
            final res    = await DailyService.markSolvedAndGetStreak();
            final badges = ProgressService.badgesFor(
              backtracked: _backtracked,
              peeked: _peeked,
              seconds: _seconds,
              parSec: ProgressService.parSeconds(grid.cellCount));
            await ProgressService.record(DailyService.todayStr(), badges);
            if (mounted) {
              setState(() {
                _streak = res.streak;
                _freezeUsed = res.freezeUsed;
                _freezeEarned = res.freezeEarned;
                _lastBadges = badges;
                _showShare = true;
              });
            }
          } else {
            if (_isEntropy) {
              // Score the board (depth × quality × difficulty) and vent entropy.
              final clean = !_backtracked && !_peeked;
              final raw = 50 + level * 15 + (clean ? 40 : 0) + max(0, 45 - _seconds);
              _runScore += (raw * _scoreMult()).round();
              _entropy = (_entropy - _kEntVent).clamp(0.0, 1.0);
            }
            _newPuzzle(advance: true);
          }
          _solve.reset();
        }
      });
    _newPuzzle();
    _loadSeen();
    AudioService.instance.startAmbient(calm: !_timed);
  }

  Future<void> _loadSeen() async {
    _seenKeys.addAll(await GuideService.seen());
    _seenLoaded = true;
    if (mounted) _checkTutorials();
  }

  /// Queue a teaching card for the Core (first play) and for any mechanic on
  /// this board the player hasn't met yet — one card each, ever.
  void _checkTutorials() {
    if (solved) return;
    bool onBoard(String key) => switch (key) {
      'seen_core'     => true,                       // every puzzle has the core
      'seen_wormhole' => grid.wormholes.isNotEmpty,
      'seen_gate'     => grid.gates.isNotEmpty,
      'seen_well'     => grid.wells.isNotEmpty,
      'seen_entangled'=> grid.hasQuantum,
      'seen_multiverse'=> grid.hasMultiverse,
      _               => false,
    };
    for (final card in kTutorialCards) {
      if (onBoard(card.seenKey) &&
          !_seenKeys.contains(card.seenKey) &&
          !_cards.contains(card)) {
        _cards.add(card);
      }
    }
    if (_cards.isNotEmpty) setState(() {});
  }

  void _dismissCard() {
    if (_cards.isEmpty) return;
    final card = _cards.removeAt(0);
    _seenKeys.add(card.seenKey);
    GuideService.markSeen(card.seenKey);
    AudioService.instance.ui();
    setState(() {});
  }

  @override
  void dispose() {
    AudioService.instance.stopAmbient();
    _timer?.cancel();
    _hintTimer?.cancel();
    _hintCellsTimer?.cancel();
    _pulse.dispose();
    _solve.dispose();
    _nudge.dispose();
    _warp.dispose();
    _unlock.dispose();
    _sling.dispose();
    _trace.dispose();
    _measure.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _seconds = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || solved || _paused || _cards.isNotEmpty || _runOver) return;
      final s = _seconds + 1;
      // Passive entropy ticks up once every _entropyTick() seconds.
      if (_isEntropy && s % _entropyTick() == 0) {
        _entropy = (_entropy + _kEntStep).clamp(0.0, 1.0);
      }
      setState(() => _seconds = s);
      if (_isEntropy && _entropy >= 1.0) _triggerGameOver();
    });
  }

  Future<void> _triggerGameOver() async {
    _stopTimer();
    HapticFeedback.heavyImpact();
    AudioService.instance.collapse();          // the heat-death sting
    final best = await ProgressService.recordEntropy(widget.difficulty.name, _runScore);
    if (mounted) setState(() { _runOver = true; _bestScore = best; });
  }

  void _restartRun() {
    AudioService.instance.ui();
    level = 1; solvedCount = 0;
    _runScore = 0; _entropy = 0; _runOver = false;
    _newPuzzle();
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  String _formatTime(int s) =>
      '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  void _newPuzzle({bool advance = false}) {
    if (!_isDaily && advance) { level++; solvedCount++; }
    final rng = _isDaily ? Random(DailyService.todaySeed()) : null;  // null → fresh random each puzzle
    var lvl = widget.fixedLevel ?? (_isDaily ? DailyService.dailyLevel() : level);

    // Quantum mode: each board rolls one "recipe" from the player's chosen types
    // — a plain board, a single exclusive mechanic (entangled/multiverse come
    // alone), or a random *combo* of the chosen additive mechanics (wormhole/
    // gate/well can share a board, as they do in Infinity). Level drives difficulty.
    var force = widget.forceFeatures;
    int? mvBoards = widget.multiverseBoards;
    if (_isQuantum) {
      const additive = {
        PuzzleFeature.wormhole, PuzzleFeature.massGate, PuzzleFeature.gravityWell,
      };
      final rnd = Random();
      final sel = widget.quantumFeatures;
      final selAdditive  = sel.where(additive.contains).toList();
      final selExclusive = sel.where((f) => !additive.contains(f)).toList();
      final recipes = <Set<PuzzleFeature> Function()>[
        if (widget.quantumNormal) () => <PuzzleFeature>{},
        for (final f in selExclusive) () => {f},
        if (selAdditive.isNotEmpty)
          () {
            final s = [...selAdditive]..shuffle(rnd);
            return s.take(1 + rnd.nextInt(s.length)).toSet();   // 1..all of them
          },
      ];
      force = recipes.isEmpty ? <PuzzleFeature>{} : recipes[rnd.nextInt(recipes.length)]();
      if (force.contains(PuzzleFeature.multiverse)) mvBoards = rnd.nextBool() ? 3 : 2;
      // Give multi-mechanic boards enough room to actually place everything (a
      // 5×5 can't fit a wormhole + gate + well). Floor the generation level — and
      // thus the board size — by how many mechanics this board is forcing.
      final floor = force.length >= 3 ? 6 : (force.length == 2 ? 3 : 0);
      if (lvl < floor) lvl = floor;
    }

    grid = PuzzleGrid.generate(lvl, rng: rng, force: force, multiverseBoards: mvBoards);
    path
      ..clear()
      ..add(grid.startCell);
    solved      = false;
    _showShare  = false;
    _backtracked = false;
    _peeked     = false;
    _lastBadges = 0;
    _freezeUsed = false;
    _freezeEarned = false;
    _clearHint();
    _nudge.reset();
    _warp.reset();
    _unlock.reset();
    _sling.reset();
    _measure.reset();
    _atomic.clear();
    _showSolution = false;     // new board → hide any revealed solution
    _hintCellsTimer?.cancel();
    _hintCells = const [];
    _trace.stop();
    _cards.clear();
    _startTimer();
    if (_seenLoaded) _checkTutorials();
    setState(() {});
  }

  void _reset() {
    if (solved) return;
    path
      ..clear()
      ..add(grid.startCell);
    _backtracked = true; _addEntropy(_kEntBacktrack);
    _clearHint();
    _warp.reset();   // portals back to their idle look
    _unlock.reset();
    _sling.reset();
    _measure.reset();
    _atomic.clear();
    HapticFeedback.mediumImpact();
    setState(() {});
  }

  /// Step back one move. Atomic moves (well launch / wormhole teleport) undo as
  /// a whole unit, not one intermediate cell.
  void _undo() {
    if (solved || path.length < 2) return;
    final last = path.length - 1;
    int? start;
    _atomic.forEach((s, len) { if (s + len - 1 == last) start = s; });
    if (start != null) {
      path.removeRange(start!, path.length);
      _atomic.remove(start);
    } else {
      path.removeLast();
    }
    _backtracked = true; _addEntropy(_kEntBacktrack);
    _clearHint();
    HapticFeedback.selectionClick();
    setState(() {});
  }

  /// Truncate the worldline back to [cell] (drops everything after it). If the
  /// tapped cell sits inside an atomic move, snap to just before that move.
  void _truncateTo(int cell) {
    if (solved) return;
    var i = path.indexOf(cell);
    if (i < 0 || i == path.length - 1) return;
    _atomic.forEach((s, len) { if (i >= s && i <= s + len - 1) i = s - 1; });
    if (i < 0) return;
    path.removeRange(i + 1, path.length);
    _atomic.removeWhere((s, len) => s > i);
    _backtracked = true; _addEntropy(_kEntBacktrack);
    _clearHint();
    HapticFeedback.selectionClick();
    setState(() {});
  }

  void _showHint(String text,
      {Duration duration = const Duration(milliseconds: 1600)}) {
    _hintTimer?.cancel();
    setState(() => _hint = text);
    _hintTimer = Timer(duration, () {
      if (mounted) setState(() => _hint = null);
    });
  }

  void _clearHint() {
    _hintTimer?.cancel();
    if (_hint != null) _hint = null;
  }

  /// True when [target] is the Black Hole, it is next in milestone order, and is
  /// reachable — but the region isn't fully consumed yet, so it must wait.
  bool _isBlackHoleEarly(int target) {
    final m = grid.milestones[target];
    if (m == null || m != grid.milestoneCount) return false;
    if (m != _milestonesVisited() + 1)          return false;
    final head = path.last;
    if (!grid.adjacent(head, target))           return false;
    if (grid.hasWall(head, target))             return false;
    if (path.contains(target))                  return false;
    return path.length != grid.fillCount - 1;
  }

  void _nudgeBlackHole() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastNudgeMs < 700) return;   // throttle repeated bumps
    _lastNudgeMs = now;
    _nudgeKind = 1;
    HapticFeedback.heavyImpact();
    AudioService.instance.denied();
    _nudge.forward(from: 0);
    _showHint('CONSUME EVERY CELL FIRST');
  }

  int _milestonesVisited() =>
      path.where((c) => grid.milestones.containsKey(c)).length;

  /// The entangled twin that has collapsed (voided), derived from the path so it
  /// auto-reverts on undo. -1 if no pair, or the pair hasn't been measured yet.
  int get _collapsedCell {
    if (!grid.hasQuantum) return -1;
    if (path.contains(grid.quantumCell)) return grid.ghostCell;
    if (path.contains(grid.ghostCell))   return grid.quantumCell;
    return -1;
  }

  bool _canStep(int target) {
    final head = path.last;
    if (!grid.adjacent(head, target)) return false;
    if (grid.hasWall(head, target))   return false;
    if (path.contains(target))        return false;
    if (target == _collapsedCell)     return false;   // a vanished twin
    final keyId = grid.gateKeyAt(head, target);   // sealed until its boson is taken
    if (keyId != null && !_keyCollected(keyId)) return false;
    final m = grid.milestones[target];
    if (m != null) {
      if (m != _milestonesVisited() + 1) return false;
      if (m == grid.milestoneCount && path.length != grid.fillCount - 1) {
        return false;
      }
    }
    // A gravity well only accepts you if its whole launch corridor is clear.
    final wdir = grid.wellDir(target);
    if (wdir != null && !_wellCorridorClear(target, wdir)) return false;
    // A wormhole forces a teleport on entry — its twin must be free to land on.
    final twin = grid.wormholeTwin(target);
    if (twin != null && path.contains(twin)) return false;
    // A multiverse bridge forces a cross-board teleport on entry — its exit must
    // be free; a one-way white mouth can't be entered by a normal step at all.
    if (grid.isBridgeEntryBlocked(target)) return false;
    final bexit = grid.bridgeExitFrom(target);
    if (bexit != null && path.contains(bexit)) return false;
    return true;
  }

  /// All [PuzzleGrid.wellRange] cells the well would fling through are in-line,
  /// wall-free and unvisited.
  bool _wellCorridorClear(int well, int dir) {
    var prev = well;
    for (var s = 1; s <= PuzzleGrid.wellRange; s++) {
      final c = well + dir * s;
      if (c < 0 || c >= grid.cellCount) return false;
      if (!grid.adjacent(prev, c))      return false;   // also catches row-wrap
      if (grid.hasWall(prev, c))        return false;
      if (path.contains(c))             return false;
      prev = c;
    }
    return true;
  }

  /// The cells a well launch consumes: [well, well+dir, … well+range·dir].
  List<int> _wellPath(int well, int dir) =>
      [for (var s = 0; s <= PuzzleGrid.wellRange; s++) well + dir * s];

  /// True when [target] is a well you could reach but whose launch is blocked.
  bool _isWellBlocked(int target) {
    final dir = grid.wellDir(target);
    if (dir == null) return false;
    final head = path.last;
    return grid.adjacent(head, target) &&
        !grid.hasWall(head, target) &&
        !path.contains(target) &&
        !_wellCorridorClear(target, dir);
  }

  void _nudgeWell() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastNudgeMs < 700) return;
    _lastNudgeMs = now;
    _nudgeKind = 3;
    HapticFeedback.heavyImpact();
    AudioService.instance.denied();
    _nudge.forward(from: 0);
    _showHint('GRAVITY WELL · LAUNCH PATH BLOCKED');
  }

  /// Has the boson with id [keyId] been collected (its cell is on the path)?
  bool _keyCollected(int keyId) =>
      grid.keys.entries.any((e) => e.value == keyId && path.contains(e.key));

  /// True when [target] is blocked only by a still-locked mass gate.
  bool _isGateBlocked(int target) {
    final head  = path.last;
    final keyId = grid.gateKeyAt(head, target);
    return keyId != null &&
        !_keyCollected(keyId) &&
        !grid.hasWall(head, target) &&
        !path.contains(target);
  }

  void _nudgeGate(int target) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastNudgeMs < 700) return;
    _lastNudgeMs = now;
    _nudgeKind = 2;
    HapticFeedback.heavyImpact();
    AudioService.instance.denied();
    _nudge.forward(from: 0);
    _showHint('GATE · GRAB THE BOSON FIRST');
  }

  /// Map a raw gesture point (box space) into board space. In the Penrose skin
  /// the board is painted rotated +45° and scaled 1/√2 about its centre, so input
  /// must be inverse-transformed (un-rotate −45°, un-scale ×√2) before hit-testing
  /// — otherwise the cell you touch wouldn't match the cell you see.
  Offset _boardLocal(Offset p) {
    if (!_penrose || grid.hasMultiverse) return p;   // Penrose is off in multiverse
    final c = _boardSize / 2;
    final v = p - Offset(c, c);
    const a = -pi / 4;
    final ca = cos(a), sa = sin(a);
    final r = Offset(v.dx * ca - v.dy * sa, v.dx * sa + v.dy * ca) * sqrt2;
    return r + Offset(c, c);
  }

  int? _cellAt(Offset p) {
    if (grid.hasMultiverse) return _layout?.cellAt(p);
    final cs = _boardSize / grid.size;
    if (p.dx < 0 || p.dy < 0 || p.dx >= _boardSize || p.dy >= _boardSize) {
      return null;
    }
    final c = (p.dx / cs).floor().clamp(0, grid.size - 1);
    final r = (p.dy / cs).floor().clamp(0, grid.size - 1);
    return r * grid.size + c;
  }

  /// How far into a cell the finger must reach (each side) before an *undo* is
  /// allowed. Only the backtrack is gated — forward stepping stays edge-to-edge
  /// responsive — so a fast swipe that grazes the previous cell's edge no longer
  /// triggers a spurious undo, but the drawing motion itself is never sticky.
  static const double _undoMargin = 0.34;

  bool _deepInside(Offset p, int cell) {
    final double fx, fy;
    if (grid.hasMultiverse) {
      final f = _layout?.fracInCell(p, cell);
      if (f == null) return false;
      fx = f.dx; fy = f.dy;
    } else {
      final cs = _boardSize / grid.size;
      fx = p.dx / cs - grid.colOf(cell);
      fy = p.dy / cs - grid.rowOf(cell);
    }
    return fx > _undoMargin && fx < 1 - _undoMargin &&
           fy > _undoMargin && fy < 1 - _undoMargin;
  }

  void _onPan(Offset local) {
    if (solved || _paused || _runOver || _cards.isNotEmpty) return;
    local = _boardLocal(local);
    final cell = _cellAt(local);
    if (cell == null || cell == path.last) return;

    if (path.length >= 2 && cell == path[path.length - 2]) {
      // Atomic moves (well launch / wormhole teleport) don't unwind by dragging
      // back through them — the Undo button handles that as one unit.
      final last = path.length - 1;
      if (_atomic.entries.any((e) => last >= e.key && last <= e.key + e.value - 1)) {
        return;
      }
      // Deliberate pull-back into the previous cell = undo; a mere edge graze
      // during forward motion is ignored.
      if (_deepInside(local, cell)) {
        path.removeLast();
        _backtracked = true; _addEntropy(_kEntBacktrack);
        _clearHint();
        HapticFeedback.selectionClick();
        setState(() {});
      }
      return;
    }

    if (_canStep(cell)) {
      // ── Gravity-well launch ─────────────────────────────────────────────
      final wdir = grid.wellDir(cell);
      if (wdir != null) {
        final launch = _wellPath(cell, wdir);   // well + the cells it flings through
        _atomic[path.length] = launch.length;   // atomic for undo
        path.addAll(launch);
        _slingFrom = launch.first;
        _slingTo   = launch.last;
        HapticFeedback.mediumImpact();
        AudioService.instance.slingshot();
        _sling.forward(from: 0);
        if (path.length == grid.fillCount) _onSolved();
        setState(() {});
        return;
      }

      // ── Wormhole forced teleport ────────────────────────────────────────
      // Entering a portal whisks you out its twin — you can't walk through it.
      final twin = grid.wormholeTwin(cell);
      if (twin != null) {
        _atomic[path.length] = 2;
        path..add(cell)..add(twin);
        _slingFrom = null; _slingTo = null;
        HapticFeedback.mediumImpact();
        AudioService.instance.warp();
        _warp.forward(from: 0);
        if (path.length == grid.fillCount) _onSolved();
        setState(() {});
        return;
      }

      // ── Multiverse bridge crossing ──────────────────────────────────────
      // Stepping onto a bridge mouth ejects you out the far board (atomic, like a
      // wormhole). One-way bridges only fire from their black mouth (enforced in
      // _canStep); two-way fire from either side.
      final bexit = grid.bridgeExitFrom(cell);
      if (bexit != null) {
        _atomic[path.length] = 2;
        path..add(cell)..add(bexit);
        _slingFrom = null; _slingTo = null;
        HapticFeedback.heavyImpact();
        AudioService.instance.bridge();
        _warp.forward(from: 0);
        if (path.length == grid.fillCount) _onSolved();
        setState(() {});
        return;
      }

      final isMs    = grid.milestones.containsKey(cell);
      final mnum    = grid.milestones[cell];
      final isLower = isMs && mnum != grid.milestoneCount;
      final isKey   = grid.keyIdAt(cell) != null;
      final isMeasure = grid.isQuantum(cell) && _collapsedCell < 0; // measuring now
      path.add(cell);
      HapticFeedback.lightImpact();
      if (isKey) {
        // Boson collected → its gate opens.
        HapticFeedback.mediumImpact();
        AudioService.instance.unlock();
        _unlock.forward(from: 0);
      }
      if (isMeasure) {
        // Superposition collapses — the twin vanishes.
        HapticFeedback.mediumImpact();
        AudioService.instance.measure();
        _measure.forward(from: 0);
      }
      if (isLower) {
        HapticFeedback.selectionClick();
        AudioService.instance.milestone(mnum!);
      } else if (!isMs && !isKey && !isMeasure) {
        AudioService.instance.step(path.length / grid.cellCount);
      }
      if (path.length == grid.fillCount) _onSolved();
      setState(() {});
    } else if (_isBlackHoleEarly(cell)) {
      _nudgeBlackHole();   // explain the block instead of silently rejecting it
    } else if (_isGateBlocked(cell)) {
      _nudgeGate(cell);
    } else if (_isWellBlocked(cell)) {
      _nudgeWell();
    }
  }

  /// Tap a visited cell to rewind the worldline to it. Tapping elsewhere does nothing.
  void _onTap(Offset local) {
    if (solved || _paused || _runOver || _cards.isNotEmpty) return;
    local = _boardLocal(local);
    final cell = _cellAt(local);
    if (cell == null) return;
    if (path.contains(cell)) _truncateTo(cell);
  }

  void _togglePause() {
    if (solved) return;
    AudioService.instance.ui();
    setState(() => _paused = !_paused);
    if (_paused) {
      AudioService.instance.stopAmbient();
    } else {
      AudioService.instance.startAmbient(calm: !_timed);
    }
  }

  Future<void> _toggleMute() async {
    await AudioService.instance.setMuted(!_muted);
    if (mounted) setState(() => _muted = AudioService.instance.muted);
    AudioService.instance.ui();   // audible only when now un-muted — a confirm
  }

  /// Reveal / hide the solved path. Playtest aid now; the hook for a premium
  /// "show solution" later. Does not change the puzzle state — just an overlay.
  void _toggleSolution() {
    if (solved) return;
    AudioService.instance.ui();
    setState(() => _showSolution = !_showSolution);
    if (_showSolution) {
      _peeked = true;          // revealing the answer forfeits the UNAIDED badge
      _addEntropy(_kEntSolution);
      _trace.repeat();
    } else {
      _trace.stop();
    }
  }

  /// Reveal the next few correct cells (a nudge, not the whole answer). Computed
  /// from the longest prefix of the player's path that matches the solution, so
  /// it points the way forward (or back onto the path if they've strayed). A
  /// premium hook: gate count/availability behind an entitlement later.
  void _showHintSteps() {
    if (solved) return;
    AudioService.instance.ui();
    final sol = grid.solution;
    var m = 0;
    while (m < path.length && m < sol.length && path[m] == sol[m]) {
      m++;
    }
    final hint = <int>[];
    for (var i = m; i < sol.length && hint.length < _hintSteps; i++) {
      if (!path.contains(sol[i])) hint.add(sol[i]);
    }
    if (hint.isEmpty) return;
    _peeked = true;            // a hint also forfeits the UNAIDED badge
    _addEntropy(_kEntHint);
    HapticFeedback.selectionClick();
    setState(() => _hintCells = hint);
    _hintCellsTimer?.cancel();
    _hintCellsTimer = Timer(const Duration(milliseconds: 4000), () {
      if (mounted) setState(() => _hintCells = const []);
    });
  }

  void _onSolved() {
    _stopTimer();
    solved = true;
    HapticFeedback.heavyImpact();
    AudioService.instance.collapse();
    _solve.forward(from: 0);
  }

  String _buildShareText() {
    final today   = DailyService.todayStr();
    final pathSet = path.toSet();
    final buf     = StringBuffer()
      ..writeln('Singularity: Collapse')
      ..writeln('Daily Region $today ✅');
    if (_lastBadges > 0) {
      final names = ProgressService.order
          .where((f) => (_lastBadges & f) != 0)
          .map(ProgressService.nameOf);
      buf.writeln('🏅 ${names.join(' · ')}');
    }
    if (_timed) buf.writeln('Time: ${_formatTime(_seconds)}');
    if (_streak > 0) buf.writeln('Streak 🔥 $_streak');
    buf.writeln();
    for (var r = 0; r < grid.size; r++) {
      for (var c = 0; c < grid.size; c++) {
        final cell = r * grid.size + c;
        buf.write(!pathSet.contains(cell)
          ? '⬛'
          : cell == path.first
            ? '🔵'
            : cell == path.last
              ? '🟣'
              : '🟡');
      }
      if (r < grid.size - 1) buf.writeln();
    }
    return buf.toString();
  }

  void _copyShare() {
    Clipboard.setData(ClipboardData(text: _buildShareText()));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Copied to clipboard!',
        style: TextStyle(fontFamily: 'monospace', letterSpacing: 1)),
      duration: Duration(seconds: 2),
      backgroundColor: Color(0xff0a1018),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final filled   = path.length;
    final total    = grid.fillCount;
    final nextTier = tierFor(
      (_milestonesVisited() + 1).clamp(1, grid.milestoneCount),
      grid.milestoneCount);
    final now      = DateTime.now().toUtc();
    final dateStr  = '${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';

    return Scaffold(
      backgroundColor: const Color(0xff04050a),
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                // ── Top bar: home · centered title · pause + mute ───────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                  child: SizedBox(
                    height: 44,
                    child: Stack(
                      children: [
                        // Padded so the screen-centered title never collides
                        // with the corner buttons; scales down if it's long.
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 100),
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                _isDaily ? 'DAILY  ·  $dateStr'
                                  : _isQuantum ? 'QUANTUM  ·  STAGE $level'
                                  : 'ENTROPY  ·  STAGE $level',
                                style: const TextStyle(
                                  color: _accent, fontSize: 18,
                                  fontFamily: 'monospace', letterSpacing: 4,
                                  fontWeight: FontWeight.bold,
                                  shadows: [Shadow(color: Color(0x66ffc24d), blurRadius: 14)])),
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _iconBtn(
                            _isDaily ? Icons.arrow_back_ios_new : Icons.home_outlined,
                            () => Navigator.pop(context)),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _iconBtn(Icons.pause_rounded, _togglePause,
                                enabled: !solved),
                              const SizedBox(width: 8),
                              _iconBtn(
                                _muted ? Icons.volume_off_rounded
                                       : Icons.volume_up_rounded,
                                _toggleMute),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Info block — bigger, brighter, breathing room ───────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                  child: Column(
                    children: [
                      Text(
                        _isDaily
                          ? '$filled / $total  CONSUMED'
                          : _isEntropy
                            ? '$filled / $total  CONSUMED      SCORE  $_runScore'
                            : '$filled / $total  CONSUMED      SOLVED  $solvedCount',
                        style: const TextStyle(
                          color: Color(0xff8aa6bc), fontSize: 12,
                          fontFamily: 'monospace', letterSpacing: 2)),
                      if (_isEntropy) ...[
                        const SizedBox(height: 12),
                        _entropyBar(),
                      ],
                      if (_timed) ...[
                        const SizedBox(height: 12),
                        Text(
                          _formatTime(_seconds),
                          style: const TextStyle(
                            color: Color(0xff6fb0d0), fontSize: 32,
                            fontFamily: 'monospace', letterSpacing: 6,
                            fontWeight: FontWeight.w300,
                            shadows: [Shadow(color: Color(0x445599bb), blurRadius: 14)]),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Builder(builder: (_) {
                        // Hint colour: teal for a "NEW" feature intro, red for a
                        // blocked-move warning, else the next tier's colour.
                        final hintColor = _hint != null && _hint!.startsWith('NEW')
                            ? const Color(0xff37e0d0)
                            : const Color(0xffff4466);
                        final color = _hint != null
                            ? hintColor
                            : solved ? Colors.white : nextTier.color;
                        return Text(
                          _hint != null
                            ? _hint!
                            : solved
                              ? 'REGION COLLAPSED'
                              : 'NEXT  ·  ${nextTier.name.toUpperCase()}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: color,
                            fontSize: 14, fontFamily: 'monospace', letterSpacing: 3,
                            fontWeight: FontWeight.bold,
                            shadows: [Shadow(
                              color: color.withValues(alpha: 0.55), blurRadius: 10)]),
                        );
                      }),
                    ],
                  ),
                ),

                // ── Board ──────────────────────────────────────────────────
                Expanded(
                  child: Center(
                    child: LayoutBuilder(
                      builder: (ctx, cons) {
                        final mv   = grid.hasMultiverse;
                        final side = (min(cons.maxWidth, cons.maxHeight) - 16)
                            .clamp(200.0, 620.0);
                        // Multiverse uses the full available band (taller than a
                        // square) so the stacked boards have room to breathe.
                        final area = mv
                            ? Size((cons.maxWidth  - 12).clamp(200.0, 640.0),
                                   (cons.maxHeight -  8).clamp(240.0, 1000.0))
                            : Size(side, side);
                        _boardSize = side;
                        _layout    = _BoardLayout.of(
                            area, grid.boardCount, grid.size, grid.cols);
                        return GestureDetector(
                          onTapUp:     (d) => _onTap(d.localPosition),
                          onPanStart:  (d) => _onPan(d.localPosition),
                          onPanUpdate: (d) => _onPan(d.localPosition),
                          child: AnimatedBuilder(
                            animation: Listenable.merge([_pulse, _solve, _nudge, _warp, _unlock, _sling, _trace, _measure]),
                            builder: (_, _) => CustomPaint(
                              size: area,
                              painter: _PuzzlePainter(
                                grid: grid,
                                path: path,
                                pulse: _pulse.value,
                                solveT: _solve.value,
                                nudge: _nudge.value,
                                nudgeKind: _nudgeKind,
                                warp: _warp.value,
                                unlock: _unlock.value,
                                sling: _sling.value,
                                slingFrom: _slingFrom,
                                slingTo: _slingTo,
                                showSolution: _showSolution,
                                traceT: _trace.value,
                                collapsedCell: _collapsedCell,
                                measureT: _measure.value,
                                accent: _accent,
                                penrose: _penrose && !mv,
                                hintCells: _hintCells,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),

                // ── Control bar — undo / reset / hint / solution ──────────────
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 4),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10, runSpacing: 8,
                    children: [
                      _ctrlBtn(Icons.undo, 'UNDO', _undo,
                        enabled: !solved && path.length > 1),
                      _ctrlBtn(Icons.refresh, 'RESET', _reset,
                        enabled: !solved && path.length > 1),
                      _ctrlBtn(Icons.lightbulb_outline, 'HINT', _showHintSteps,
                        enabled: !solved, active: _hintCells.isNotEmpty),
                      _ctrlBtn(
                        _showSolution ? Icons.visibility : Icons.visibility_outlined,
                        'SOLUTION', _toggleSolution,
                        enabled: !solved, active: _showSolution),
                    ],
                  ),
                ),

                // ── Footer ─────────────────────────────────────────────────
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 4, 24, 10),
                  child: Text(
                    'consume objects in order · fill every cell · finish on the black hole',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xff3a526a), fontSize: 9.5,
                      fontFamily: 'monospace', letterSpacing: 1, height: 1.5)),
                ),
              ],
            ),
          ),

          // ── Pause overlay — blocks out the entire puzzle ────────────────
          if (_paused) _buildPauseOverlay(),

          // ── First-encounter tutorial card ───────────────────────────────
          if (_cards.isNotEmpty) _buildTutorialCard(_cards.first),

          // ── Share overlay (daily mode, after solve) ─────────────────────
          if (_showShare) _buildShareOverlay(),
          if (_runOver) _buildGameOverOverlay(),
        ],
      ),
    );
  }

  /// Fully opaque overlay so the board can't be studied while paused.
  /// A teaching card shown the first time a mechanic is met. The board stays
  /// dimly visible behind it so the player can see the real thing.
  Widget _buildTutorialCard(GuideEntry e) => Positioned.fill(
    child: Container(
      color: const Color(0xcc04050a),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 36),
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
          decoration: BoxDecoration(
            color: const Color(0xff0a1018),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _accent.withValues(alpha: 0.5), width: 1.5),
            boxShadow: [BoxShadow(
              color: _accent.withValues(alpha: 0.15), blurRadius: 30, spreadRadius: 4)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('NEW',
                style: TextStyle(
                  color: Color(0xff6688aa), fontSize: 10, fontFamily: 'monospace',
                  letterSpacing: 4)),
              const SizedBox(height: 14),
              GuideIcon(e.id, size: 64),
              const SizedBox(height: 14),
              Text(e.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _accent, fontSize: 18, fontFamily: 'monospace',
                  fontWeight: FontWeight.bold, letterSpacing: 3,
                  shadows: [Shadow(color: Color(0x66ffc24d), blurRadius: 12)])),
              const SizedBox(height: 14),
              Text(e.body,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xffaec4d6), fontSize: 12.5,
                  fontFamily: 'monospace', height: 1.6)),
              const SizedBox(height: 24),
              _overlayBtn('GOT IT', _accent, _dismissCard),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _buildPauseOverlay() => Positioned.fill(
    child: Container(
      color: const Color(0xff04050a),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, _) {
                final v = sin(_pulse.value * 2 * pi) * 0.5 + 0.5;
                return Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black,
                    border: Border.all(color: const Color(0xffbb55ff), width: 2),
                    boxShadow: [BoxShadow(
                      color: const Color(0xffbb55ff).withValues(alpha: 0.22 + v * 0.22),
                      blurRadius: 20 + v * 12, spreadRadius: 2 + v * 4)],
                  ),
                );
              },
            ),
            const SizedBox(height: 28),
            const Text('PAUSED',
              style: TextStyle(
                color: Colors.white, fontSize: 26, fontFamily: 'monospace',
                fontWeight: FontWeight.bold, letterSpacing: 6,
                shadows: [Shadow(color: Color(0xffbb55ff), blurRadius: 20)])),
            if (_timed) ...[
              const SizedBox(height: 8),
              Text(_formatTime(_seconds),
                style: const TextStyle(
                  color: Color(0xff6699bb), fontSize: 14,
                  fontFamily: 'monospace', letterSpacing: 3)),
            ],
            const SizedBox(height: 36),
            _overlayBtn('RESUME', _accent, _togglePause),
            const SizedBox(height: 12),
            _overlayBtn(_muted ? 'UNMUTE' : 'MUTE', const Color(0xff7799aa),
              _toggleMute),
            const SizedBox(height: 12),
            _overlayBtn('HOME', const Color(0xff7799aa),
              () => Navigator.pop(context)),
          ],
        ),
      ),
    ),
  );

  // Achievement-badge icon + colour for a flag.
  static (IconData, Color) _badgeStyle(int flag) => switch (flag) {
    ProgressService.perfect => (Icons.verified, Color(0xff66ffb0)),
    ProgressService.unaided => (Icons.visibility_off, Color(0xff7fd8ff)),
    ProgressService.swift   => (Icons.bolt, Color(0xffffc24d)),
    _                       => (Icons.local_fire_department, Color(0xffff7a4d)),
  };

  Widget _badgeRow(int badges) {
    final earned = ProgressService.order.where((f) => (badges & f) != 0).toList();
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10, runSpacing: 8,
      children: [for (final f in earned) _badgeChip(f)],
    );
  }

  Widget _badgeChip(int flag) {
    final (icon, c) = _badgeStyle(flag);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: c, size: 16),
          const SizedBox(width: 6),
          Text(ProgressService.nameOf(flag),
            style: TextStyle(
              color: c, fontSize: 11, fontFamily: 'monospace',
              fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        ],
      ),
    );
  }

  /// The Infinity entropy meter — teal → amber → red as it fills.
  Widget _entropyBar() {
    final e   = _entropy.clamp(0.0, 1.0);
    final col = e < 0.5 ? const Color(0xff37e0d0)
              : e < 0.8 ? const Color(0xffffc24d)
              : const Color(0xffff4466);
    return SizedBox(
      width: 232,
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('ENTROPY', style: TextStyle(
            color: Color(0xff5a7488), fontSize: 9,
            fontFamily: 'monospace', letterSpacing: 2)),
          Text('${(e * 100).round()}%', style: TextStyle(
            color: col, fontSize: 9, fontFamily: 'monospace',
            letterSpacing: 1, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 4),
        Container(
          height: 9,
          decoration: BoxDecoration(
            color: const Color(0xff0e1c28),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: const Color(0xff1c2e3c), width: 1)),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: e <= 0 ? 0.0 : e),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOut,
            builder: (_, v, _) => FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: v,
              child: Container(decoration: BoxDecoration(
                color: col,
                borderRadius: BorderRadius.circular(5),
                boxShadow: e > 0.7
                  ? [BoxShadow(color: col.withValues(alpha: 0.7), blurRadius: 8)]
                  : null)),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildGameOverOverlay() {
    final best = _runScore >= _bestScore;
    return Container(
      color: const Color(0xf204050a),
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('HEAT DEATH',
                style: TextStyle(
                  color: Color(0xffff4466), fontSize: 26, fontFamily: 'monospace',
                  fontWeight: FontWeight.bold, letterSpacing: 5,
                  shadows: [Shadow(color: Color(0x88ff4466), blurRadius: 22)])),
              const SizedBox(height: 6),
              const Text('ENTROPY MAXED · THE REGION COLLAPSED',
                style: TextStyle(
                  color: Color(0xff8aa6bc), fontSize: 10,
                  fontFamily: 'monospace', letterSpacing: 2)),
              const SizedBox(height: 36),
              Text('$_runScore', style: const TextStyle(
                color: _accent, fontSize: 56, fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                shadows: [Shadow(color: Color(0x66ffc24d), blurRadius: 20)])),
              const Text('SCORE', style: TextStyle(
                color: Color(0xff5a7488), fontSize: 10,
                fontFamily: 'monospace', letterSpacing: 3)),
              const SizedBox(height: 14),
              Text(best ? '★ NEW BEST ★' : 'BEST  $_bestScore',
                style: TextStyle(
                  color: best ? _accent : const Color(0xff7799aa), fontSize: 12,
                  fontFamily: 'monospace', letterSpacing: 2,
                  fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('REACHED STAGE $level', style: const TextStyle(
                color: Color(0xff5a7488), fontSize: 10,
                fontFamily: 'monospace', letterSpacing: 2)),
              const SizedBox(height: 40),
              _overlayBtn('NEW RUN', _accent, _restartRun),
              const SizedBox(height: 12),
              _overlayBtn('HOME', const Color(0xff7799aa),
                () => Navigator.pop(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShareOverlay() {
    final shareText = _buildShareText();
    return Container(
      color: const Color(0xee04050a),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('REGION COLLAPSED',
              style: TextStyle(
                color: Colors.white, fontSize: 22, fontFamily: 'monospace',
                fontWeight: FontWeight.bold, letterSpacing: 4,
                shadows: [Shadow(color: Color(0xffbb55ff), blurRadius: 20)])),

            if (_isDaily && _lastBadges > 0) ...[
              const SizedBox(height: 16),
              _badgeRow(_lastBadges),
            ],

            if (_timed && _seconds > 0) ...[
              const SizedBox(height: 6),
              Text(_formatTime(_seconds),
                style: const TextStyle(
                  color: Color(0xff6699bb), fontSize: 13,
                  fontFamily: 'monospace', letterSpacing: 3)),
            ],

            if (_streak > 0) ...[
              const SizedBox(height: 6),
              Text('$_streak DAY STREAK',
                style: const TextStyle(
                  color: Color(0xffbb55ff), fontSize: 12,
                  fontFamily: 'monospace', letterSpacing: 3,
                  shadows: [Shadow(color: Color(0x66bb55ff), blurRadius: 10)])),
            ],
            if (_freezeUsed || _freezeEarned) ...[
              const SizedBox(height: 6),
              Text(_freezeUsed ? '❄  STREAK SAVED · FREEZE USED'
                               : '❄  STREAK FREEZE EARNED',
                style: const TextStyle(
                  color: Color(0xff7fd8ff), fontSize: 11,
                  fontFamily: 'monospace', letterSpacing: 2,
                  shadows: [Shadow(color: Color(0x667fd8ff), blurRadius: 10)])),
            ],

            const SizedBox(height: 28),

            // Share card preview
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xff0a1018),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xff223344)),
              ),
              child: Text(shareText,
                style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 11,
                  color: Color(0xffccddee), height: 1.6, letterSpacing: 1)),
            ),

            const SizedBox(height: 28),

            _overlayBtn('COPY SHARE CARD', const Color(0xffffc24d), _copyShare),
            const SizedBox(height: 12),
            _overlayBtn('HOME', const Color(0xff7799aa),
              () => Navigator.pop(context)),
          ],
        ),
      ),
    );
  }

  Widget _overlayBtn(String label, Color color, VoidCallback onTap) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 56),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xff0a1018),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.55), width: 1.5),
        ),
        child: Center(child: Text(label,
          style: TextStyle(
            color: color, fontSize: 12, fontFamily: 'monospace',
            fontWeight: FontWeight.bold, letterSpacing: 2,
            shadows: [Shadow(color: color.withValues(alpha: 0.35), blurRadius: 8)]))),
      ),
    );

  Widget _iconBtn(IconData icon, VoidCallback onTap, {bool enabled = true}) =>
    GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: const Color(0xff0a1018),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Color(enabled ? 0xff223344 : 0xff15202c), width: 1),
        ),
        child: Icon(icon,
          color: Color(enabled ? 0xff7799aa : 0xff35485a), size: 20),
      ),
    );

  /// Larger labelled control for the lower bar (undo / reset).
  Widget _ctrlBtn(IconData icon, String label, VoidCallback onTap,
      {bool enabled = true, bool active = false}) {
    final c = active
        ? _accent
        : Color(enabled ? 0xff7799aa : 0xff35485a);
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: active ? const Color(0xff1b1606) : const Color(0xff0a1018),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active
                ? _accent
                : Color(enabled ? 0xff223344 : 0xff15202c),
            width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: c, size: 18),
            const SizedBox(width: 7),
            Text(label,
              style: TextStyle(
                color: c, fontSize: 12, fontFamily: 'monospace',
                fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          ],
        ),
      ),
    );
  }
}

class _PuzzlePainter extends CustomPainter {
  final PuzzleGrid grid;
  final List<int>  path;
  final double     pulse;
  final double     solveT;   // 0 → 1 collapse celebration
  final double     nudge;    // 0 → 1 "not yet" warning flash
  final int        nudgeKind; // 0 none · 1 black hole · 2 mass gate
  final double     warp;     // 0 → 1 wormhole teleport flash
  final double     unlock;   // 0 → 1 mass-gate open ripple
  final double     sling;    // 0 → 1 gravity-well launch streak
  final int?       slingFrom;
  final int?       slingTo;
  final bool       showSolution;
  final double     traceT;    // 0 → 1 solution tracer sweep position
  final int        collapsedCell; // entangled twin that vanished (-1 none)
  final double     measureT;  // 0 → 1 entangled collapse flash
  final Color      accent;
  final bool       penrose;   // tilt the board 45° (spacetime-diagram skin)
  final List<int>  hintCells;  // a few next-step hint cells to highlight

  static const Color _portal  = Color(0xff37e0d0);  // wormhole teal
  static const Color _boson   = Color(0xff66ffb0);  // boson / mass-gate green
  static const Color _well    = Color(0xffff5ca8);  // gravity-well magenta
  static const Color _soln    = Color(0xff7fd8ff);  // solution-reveal cyan
  static const Color _quantum = Color(0xffc9b8ff);  // entangled lavender
  static const Color _universe2 = Color(0xff36d0ff); // multiverse board-2 (azure)
  static const Color _universe3 = Color(0xffff79c0); // multiverse board-3 (rose)

  /// Signature colour of a universe (board): gold, azure, rose.
  Color _universeColor(int board) => switch (board) {
    0 => accent,
    1 => _universe2,
    _ => _universe3,
  };

  _PuzzlePainter({
    required this.grid,
    required this.path,
    required this.pulse,
    required this.solveT,
    required this.nudge,
    required this.nudgeKind,
    required this.warp,
    required this.unlock,
    required this.sling,
    required this.slingFrom,
    required this.slingTo,
    required this.showSolution,
    required this.traceT,
    required this.collapsedCell,
    required this.measureT,
    required this.accent,
    required this.penrose,
    required this.hintCells,
  });

  // ── Collapse timeline ─────────────────────────────────────────────────────
  // 0.00–0.35  implosion   board contracts toward the black hole
  // 0.35–0.45  flash       white burst at the singularity
  // 0.45–1.00  zoom-out    region shrinks to a point; a galaxy is revealed
  double _collapseScale(double t) {
    if (t < 0.35) return 1.0 - 0.16 * Curves.easeIn.transform(t / 0.35);
    if (t < 0.45) return 0.84;
    return 0.84 * (1 - Curves.easeInCubic.transform((t - 0.45) / 0.55));
  }

  double _contentAlpha(double t) =>
      t <= 0.5 ? 1.0 : (1 - (t - 0.5) / 0.35).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final mv     = grid.hasMultiverse;
    final n      = grid.size;
    final layout = mv ? _BoardLayout.of(size, grid.boardCount, n, grid.cols) : null;
    final cell   = mv ? layout!.cell : size.width / n;
    final pulseV = sin(pulse * 2 * pi) * 0.5 + 0.5;

    // Cell-centre on screen. Multiverse maps through the per-board layout, so a
    // single `center(globalCell)` works across both boards (and the worldline
    // naturally lifts the pen across the gap at a bridge).
    Offset center(int i) => mv
      ? layout!.center(i)
      : Offset((grid.colOf(i) + 0.5) * cell, (grid.rowOf(i) + 0.5) * cell);

    final bounds   = Offset.zero & size;
    final bhCenter = center(grid.blackHoleCell);

    // Where the black hole actually appears on screen. In the Penrose skin the
    // board is rotated, so its visible position is the forward-transformed
    // bhCenter — the implosion and the collapse celebration must pivot there, not
    // on the un-rotated cell centre, or the region would crunch to the wrong spot.
    Offset pivot = bhCenter;
    if (penrose) {
      final c = size.center(Offset.zero);
      final v = (bhCenter - c) / sqrt2;
      const a = pi / 4;
      pivot = Offset(v.dx * cos(a) - v.dy * sin(a),
                     v.dx * sin(a) + v.dy * cos(a)) + c;
    }

    // During the collapse: reveal a starfield behind the board, then scale all
    // board content down toward the black hole (the region implodes into a
    // single point of a wider galaxy). A fade layer dissolves the old region.
    final collapsing   = solveT > 0;
    final contentAlpha = _contentAlpha(solveT);
    if (collapsing) {
      _drawStarfield(canvas, size, ((solveT - 0.4) / 0.3).clamp(0.0, 1.0));
      final s = _collapseScale(solveT);
      canvas.save();
      canvas.translate(pivot.dx, pivot.dy);
      canvas.scale(s);
      canvas.translate(-pivot.dx, -pivot.dy);
    }
    final fadeLayer = collapsing && contentAlpha < 0.99;
    if (fadeLayer) {
      canvas.saveLayer(bounds,
        Paint()..color = Colors.white.withValues(alpha: contentAlpha));
    }

    // ── Penrose / spacetime skin ──────────────────────────────────────────────
    // Tilt the whole board +45° (scaled 1/√2 to stay inscribed in its box) so the
    // axis-aligned grid becomes a lattice of 45° light cones and the worldline
    // reads as a null-ray path — a Penrose diagram crunching toward the
    // singularity. Wraps only the board content; the HUD and the collapse
    // celebration (drawn in screen space) stay upright. Input is inverse-
    // transformed in _boardLocal so taps still land on the cell you see.
    if (penrose) {
      final c = size.center(Offset.zero);
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(pi / 4);
      canvas.scale(1 / sqrt2);
      canvas.translate(-c.dx, -c.dy);
    }

    // Board backdrop(s) + faint cell grid. Multiverse draws one dark panel per
    // board at its layout origin; a single board fills the whole area.
    RRect? rrect;   // single-board panel (reused for the outer border below)
    final gridPaint = Paint()
      ..color = const Color(0xff142030)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    if (mv) {
      final boardW = layout!.boardW, boardH = layout.boardH;
      for (var b = 0; b < layout.origins.length; b++) {
        final o = layout.origins[b];
        // Each universe carries its own tint so the *board* is identifiable even
        // when the worldline on it is another universe's colour. Board 1 stays the
        // default dark; later boards get a faint signature wash on panel + grid.
        final tint  = b == 0 ? null : _universeColor(b);
        final panel = tint == null
            ? const Color(0xff070b12)
            : Color.lerp(const Color(0xff070b12), tint, 0.05)!;
        final glow  = tint == null
            ? const Color(0xff142030)
            : Color.lerp(const Color(0xff142030), tint, 0.30)!;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(o.dx, o.dy, boardW, boardH), const Radius.circular(8)),
          Paint()..color = panel);
        final gp = Paint()..color = glow
          ..style = PaintingStyle.stroke ..strokeWidth = 1;
        for (var i = 0; i <= grid.cols; i++) {
          canvas.drawLine(Offset(o.dx + i * cell, o.dy),
                          Offset(o.dx + i * cell, o.dy + boardH), gp);
        }
        for (var i = 0; i <= n; i++) {
          canvas.drawLine(Offset(o.dx, o.dy + i * cell),
                          Offset(o.dx + boardW, o.dy + i * cell), gp);
        }
      }
    } else {
      rrect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10));
      canvas.drawRRect(rrect, Paint()..color = const Color(0xff070b12));
      for (var i = 0; i <= n; i++) {
        canvas.drawLine(Offset(i * cell, 0), Offset(i * cell, size.height), gridPaint);
        canvas.drawLine(Offset(0, i * cell), Offset(size.width, i * cell), gridPaint);
      }
    }

    // Per-step "origin universe": the board each leg *departed from* (the first
    // leg from the start board; each later leg from the near side of the bridge
    // it crossed). Used to colour the worldline + fill so a leg visiting board 2
    // from board 1 stays gold, while the *return* leg on board 1 shows board 2's
    // colour — making inter-board travel legible.
    final originBoard = List<int>.filled(path.length, 0);
    if (path.isNotEmpty) {
      var ob = grid.boardOf(path.first);
      for (var i = 0; i < path.length; i++) {
        if (i > 0 && !grid.adjacent(path[i - 1], path[i])) {
          ob = grid.boardOf(path[i - 1]);          // departed from the near side
        }
        originBoard[i] = ob;
      }
    }
    Color legColor(int stepIndex) =>
        _universeColor(mv ? originBoard[stepIndex] : 0);

    // Filled-cell tint (centre-based → board-aware, coloured by origin universe)
    for (var i = 0; i < path.length; i++) {
      canvas.drawRect(
        Rect.fromCenter(center: center(path[i]), width: cell - 3, height: cell - 3),
        Paint()..color = legColor(i).withValues(alpha: 0.10));
    }

    // Walls — on the shared edge between the two cells (centre-midpoint → board-aware)
    final wallPaint = Paint()
      ..color = const Color(0xff5a6e84)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    final cc = grid.cellCount;
    for (final key in grid.walls) {
      final lo = key ~/ cc, hi = key % cc;
      final mid = (center(lo) + center(hi)) / 2;
      if (hi - lo == 1) {                       // horizontal neighbours → vertical wall
        canvas.drawLine(mid + Offset(0, -cell / 2 + 2),
                        mid + Offset(0, cell / 2 - 2), wallPaint);
      } else {                                  // vertical neighbours → horizontal wall
        canvas.drawLine(mid + Offset(-cell / 2 + 2, 0),
                        mid + Offset(cell / 2 - 2, 0), wallPaint);
      }
    }

    // ── Boson keys ───────────────────────────────────────────────────────────
    // The collectible that opens a mass gate. A bright green mote with a halo
    // and a little spark cross; dims once collected.
    grid.keys.forEach((cellIdx, _) {
      final pos  = center(cellIdx);
      final done = path.contains(cellIdx);
      final a    = done ? 0.22 : 1.0;
      final rad  = cell * 0.16 * (0.92 + pulseV * 0.16);
      canvas.drawCircle(pos, rad * 2.4, Paint()..color = _boson.withValues(alpha: a * 0.22));
      canvas.drawCircle(pos, rad, Paint()..color = _boson.withValues(alpha: a));
      if (!done) {
        final sp = Paint()
          ..color = Colors.white.withValues(alpha: 0.85)
          ..strokeWidth = 1.6..strokeCap = StrokeCap.round;
        canvas.drawLine(pos - Offset(rad * 1.5, 0), pos + Offset(rad * 1.5, 0), sp);
        canvas.drawLine(pos - Offset(0, rad * 1.5), pos + Offset(0, rad * 1.5), sp);
      }
    });

    // ── Mass gates ───────────────────────────────────────────────────────────
    // A green bar across an edge: solid + glowing while its boson is uncollected,
    // faint once open. Ripples green when it just opened, flashes red on a bump.
    if (grid.gates.isNotEmpty) {
      grid.gates.forEach((key, keyId) {
        final lo = key ~/ cc, hi = key % cc;
        final open  = grid.keys.entries
            .any((e) => e.value == keyId && path.contains(e.key));
        final flash = (nudgeKind == 2 && !open) ? nudge : 0.0;
        final col   = Color.lerp(_boson, const Color(0xffff4466), flash)!;
        final paint = Paint()
          ..color = col.withValues(alpha: open ? 0.26 : 0.95)
          ..style = PaintingStyle.stroke
          ..strokeWidth = open ? 2.5 : 4.5 + flash * 2
          ..strokeCap = StrokeCap.round;
        if (!open) paint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

        late Offset p1, p2;
        if (hi - lo == 1 && grid.rowOf(lo) == grid.rowOf(hi)) {
          final x = grid.colOf(hi) * cell, y = grid.rowOf(lo) * cell;
          p1 = Offset(x, y + cell * 0.16); p2 = Offset(x, y + cell * 0.84);
        } else {
          final y = grid.rowOf(hi) * cell, x = grid.colOf(lo) * cell;
          p1 = Offset(x + cell * 0.16, y); p2 = Offset(x + cell * 0.84, y);
        }
        canvas.drawLine(p1, p2, paint);
        // Open ripple
        if (open && unlock > 0) {
          final mid = (p1 + p2) / 2;
          canvas.drawCircle(mid, cell * (0.2 + unlock * 0.7),
            Paint()
              ..color = _boson.withValues(alpha: (1 - unlock) * 0.7)
              ..style = PaintingStyle.stroke..strokeWidth = 3 * (1 - unlock));
        }
      });
    }

    // ── Wormhole portals ────────────────────────────────────────────────────
    if (grid.wormholes.isNotEmpty) {
      final drawn = <int>{};
      grid.wormholes.forEach((a, b) {
        if (drawn.contains(a)) return;
        drawn..add(a)..add(b);
        final pa = center(a), pb = center(b);
        // Faint connector so the link reads at a glance.
        canvas.drawLine(pa, pb, Paint()
          ..color = _portal.withValues(alpha: 0.12)
          ..strokeWidth = 1.5
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
        _drawPortal(canvas, pa, cell, pulseV);
        _drawPortal(canvas, pb, cell, pulseV);
      });
    }

    // ── Gravity wells ────────────────────────────────────────────────────────
    // A magenta swirl with an arrow + dots showing the fixed launch (it flings
    // you `wellRange` cells that way). Flashes red on a blocked-launch bump.
    if (grid.wells.isNotEmpty) {
      grid.wells.forEach((cellIdx, dir) {
        final pos  = center(cellIdx);
        final done = path.contains(cellIdx);
        final v    = dir == 1 ? const Offset(1, 0)
                   : dir == -1 ? const Offset(-1, 0)
                   : dir == grid.size ? const Offset(0, 1)
                   : const Offset(0, -1);
        final flash = nudgeKind == 3 ? nudge : 0.0;
        final col   = Color.lerp(_well, const Color(0xffff4466), flash)!
            .withValues(alpha: done ? 0.3 : 1.0);
        final spin = pulse * 2 * pi;
        for (var k = 0; k < 2; k++) {
          final rect = Rect.fromCircle(center: pos, radius: cell * (0.22 + k * 0.1));
          canvas.drawArc(rect, spin + k * pi, pi * 1.25, false,
            Paint()..color = col.withValues(alpha: (done ? 0.3 : 0.85) - k * 0.25)
              ..style = PaintingStyle.stroke..strokeWidth = 2.5..strokeCap = StrokeCap.round);
        }
        for (var s = 1; s <= PuzzleGrid.wellRange; s++) {
          canvas.drawCircle(pos + v * (cell * s), 2.4,
            Paint()..color = col.withValues(alpha: done ? 0.2 : 0.5));
        }
        // Arrowhead at the landing cell.
        final tip  = pos + v * (cell * PuzzleGrid.wellRange.toDouble());
        final perp = Offset(-v.dy, v.dx);
        final ap = Paint()..color = col..strokeWidth = 2.5
          ..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
        canvas.drawLine(tip - v * (cell * 0.18) + perp * (cell * 0.14), tip, ap);
        canvas.drawLine(tip - v * (cell * 0.18) - perp * (cell * 0.14), tip, ap);
      });
    }

    // ── Entangled pair ───────────────────────────────────────────────────────
    // Two superposed twins flicker out of phase, joined by a shimmering thread,
    // until one is measured; then its twin collapses to a fading void.
    if (grid.hasQuantum) {
      final a = center(grid.quantumCell), b = center(grid.ghostCell);
      final collapsed = collapsedCell;
      if (collapsed < 0) {
        // Superposition: dashed thread + two out-of-phase ghosts.
        final dash = Paint()
          ..color = _quantum.withValues(alpha: 0.35 + pulseV * 0.25)
          ..strokeWidth = 1.6;
        const seg = 7.0;
        final dir = (b - a); final len = dir.distance;
        final unit = len == 0 ? Offset.zero : dir / len;
        for (var d = 0.0; d < len; d += seg * 2) {
          canvas.drawLine(a + unit * d, a + unit * (d + seg).clamp(0, len), dash);
        }
        for (final pair in [[a, pulseV], [b, 1 - pulseV]]) {
          final p = pair[0] as Offset;
          final ph = pair[1] as double;       // out-of-phase brightness
          final rad = cell * 0.20;
          canvas.drawCircle(p, rad * 1.8,
            Paint()..color = _quantum.withValues(alpha: 0.10 + ph * 0.22));
          canvas.drawCircle(p, rad,
            Paint()..color = _quantum.withValues(alpha: 0.35 + ph * 0.5));
          canvas.drawCircle(p, rad,
            Paint()..color = _quantum.withValues(alpha: 0.6 + ph * 0.4)
              ..style = PaintingStyle.stroke..strokeWidth = 1.6);
        }
      } else {
        // The vanished twin: a quick implode (measureT) then a clearly-dead void
        // — a recessed pit, a *broken* ghost-ring, and a faint ✕ so the player
        // reads it as "collapsed · cannot step here", not an empty cell.
        final v = center(collapsed);
        final t = measureT;
        if (t > 0 && t < 1) {
          // Collapse flash: a lavender ring snapping inward as it implodes.
          canvas.drawCircle(v, cell * 0.42 * (1 - t),
            Paint()..color = _quantum.withValues(alpha: (1 - t) * 0.6)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
          canvas.drawCircle(v, cell * 0.42 * (1 - t * 0.5),
            Paint()..color = _quantum.withValues(alpha: (1 - t) * 0.5)
              ..style = PaintingStyle.stroke ..strokeWidth = 2);
        }
        // Recessed dark pit so the cell reads as a hole, not blank space.
        canvas.drawCircle(v, cell * 0.34, Paint()..color = const Color(0xff09060f));
        canvas.drawCircle(v, cell * 0.34, Paint()
          ..color = _quantum.withValues(alpha: 0.16)
          ..style = PaintingStyle.stroke ..strokeWidth = 1);
        // Broken (dashed) lavender ghost-ring: residue of the collapsed twin.
        final rr   = cell * 0.30;
        final ring = Paint()
          ..color = _quantum.withValues(alpha: 0.36)
          ..style = PaintingStyle.stroke ..strokeWidth = 1.5;
        const dashes = 12;
        for (var k = 0; k < dashes; k++) {
          final a0 = (k / dashes) * 2 * pi;
          canvas.drawArc(Rect.fromCircle(center: v, radius: rr),
            a0, (2 * pi / dashes) * 0.55, false, ring);
        }
        // Faint ✕ — unmistakably "no entry".
        final xr = cell * 0.15;
        final xP = Paint()
          ..color = _quantum.withValues(alpha: 0.42)
          ..style = PaintingStyle.stroke ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(v + Offset(-xr, -xr), v + Offset(xr, xr), xP);
        canvas.drawLine(v + Offset(xr, -xr), v + Offset(-xr, xr), xP);
      }
    }

    // ── Bridges (multiverse) ──────────────────────────────────────────────────
    // Cross-board links, drawn under the worldline so the trace leaps along them.
    // Two-way = a calm teal traversable wormhole (portal both ends); one-way = an
    // Einstein–Rosen bridge: a dark black mouth feeding a radiant white hole.
    if (mv) {
      for (final br in grid.bridges) {
        final pa = center(br.a), pb = center(br.b);
        // A mouth is coloured by the universe it takes you TO (its other end), so
        // clustered portals are told apart by destination at a glance. The
        // connector takes the spoke (non-hub) universe's colour to group the pair.
        final boardA = grid.boardOf(br.a), boardB = grid.boardOf(br.b);
        final destA  = _universeColor(boardB);   // mouth a → board of b
        final destB  = _universeColor(boardA);   // mouth b → board of a
        final connCol = _universeColor(boardA == 0 ? boardB : boardA);
        final ctrl = Offset((pa.dx + pb.dx) / 2 + (pb.dy - pa.dy) * 0.16,
                            (pa.dy + pb.dy) / 2 + (pa.dx - pb.dx) * 0.16);
        final conn = Path()
          ..moveTo(pa.dx, pa.dy)
          ..quadraticBezierTo(ctrl.dx, ctrl.dy, pb.dx, pb.dy);
        _dashedPath(canvas, conn, Paint()
          ..color = connCol.withValues(alpha: 0.4 + pulseV * 0.22)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round);
        if (br.oneWay) {
          _drawBlackMouth(canvas, pa, cell, ring: destA);
          _drawWhiteHole(canvas, pb, cell, pulseV);
        } else {
          _drawPortal(canvas, pa, cell, pulseV, color: destA);
          _drawPortal(canvas, pb, cell, pulseV, color: destB);
        }
      }
    }

    // ── Worldline ──────────────────────────────────────────────────────────
    // Drawn as contiguous same-board runs (a non-grid step — wormhole or bridge —
    // lifts the pen), each coloured by the universe it's traced in. So board 1 is
    // gold, board 2 is its own colour, and the *return* leg to board 1 is gold
    // again → you can read inter-board travel at a glance.
    if (path.length >= 2) {
      void drawRun(int start, int endExclusive) {
        if (endExclusive - start < 2) return;
        final col = legColor(start);          // whole run shares one origin
        final p = Path()
          ..moveTo(center(path[start]).dx, center(path[start]).dy);
        for (var j = start + 1; j < endExclusive; j++) {
          p.lineTo(center(path[j]).dx, center(path[j]).dy);
        }
        canvas.drawPath(p, Paint()
          ..color = col.withValues(alpha: 0.26)
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.60
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
        canvas.drawPath(p, Paint()
          ..color = col
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.28
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round);
      }
      var runStart = 0;
      for (var i = 1; i < path.length; i++) {
        // A wormhole/bridge jump isn't a grid edge — end the run there (the
        // portals/mouths carry the connection visually).
        if (!grid.adjacent(path[i - 1], path[i])) {
          drawRun(runStart, i);
          runStart = i;
        }
      }
      drawRun(runStart, path.length);
    }

    // ── Measured (chosen) twin ───────────────────────────────────────────────
    // Once superposition collapses, keep the surviving twin marked on top of the
    // worldline so the player can see which branch they committed to (it would
    // otherwise be hidden under the trace and lose its quantum identity).
    if (grid.hasQuantum && collapsedCell >= 0) {
      final chosen = collapsedCell == grid.quantumCell
          ? grid.ghostCell : grid.quantumCell;
      final c = center(chosen);
      final r = cell * 0.20;
      canvas.drawCircle(c, r * 1.9,
        Paint()..color = _quantum.withValues(alpha: 0.20 + pulseV * 0.10)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
      canvas.drawCircle(c, r, Paint()..color = _quantum.withValues(alpha: 0.9));
      canvas.drawCircle(c, r, Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke ..strokeWidth = 1.6);
      canvas.drawCircle(c - Offset(r * 0.3, r * 0.3), r * 0.34,
        Paint()..color = Colors.white.withValues(alpha: 0.55));
    }

    // ── Gravity-well launch streak ───────────────────────────────────────────
    if (sling > 0 && slingFrom != null && slingTo != null) {
      final a = 1 - sling;
      final f = center(slingFrom!), t = center(slingTo!);
      canvas.drawLine(f, t, Paint()
        ..color = _well.withValues(alpha: a * 0.85)
        ..strokeWidth = cell * 0.30 * (1 - sling * 0.4)
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
      final hp = Offset.lerp(f, t, Curves.easeOut.transform(sling))!;
      canvas.drawCircle(hp, cell * 0.14, Paint()..color = Colors.white.withValues(alpha: a));
    }

    // ── Cosmic milestones ──────────────────────────────────────────────────
    final visited = path.where((c) => grid.milestones.containsKey(c)).length;
    final count   = grid.milestoneCount;
    grid.milestones.forEach((cellIdx, mnum) {
      final pos  = center(cellIdx);
      final tier = tierFor(mnum, count);
      final done = mnum <= visited;
      final next = mnum == visited + 1;
      final frac = count > 1 ? (mnum - 1) / (count - 1) : 0.0;
      final rad  = cell * (0.20 + frac * 0.14);

      if (next) {
        // Soft halo + a crisp pulsing ring so the next target reads clearly.
        canvas.drawCircle(pos, rad + 6 + pulseV * 4,
          Paint()..color = tier.color.withValues(alpha: 0.42)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
        canvas.drawCircle(pos, rad + 4 + pulseV * 3,
          Paint()..color = tier.color.withValues(alpha: 0.55 + pulseV * 0.25)
            ..style = PaintingStyle.stroke ..strokeWidth = 2);
      }

      if (tier.isBlackHole) {
        canvas.save();
        canvas.translate(pos.dx, pos.dy);
        canvas.scale(1.0, 0.34);
        canvas.drawCircle(Offset.zero, rad * 1.7,
          Paint()..color = const Color(0xffff7722).withValues(alpha: 0.85)
            ..style = PaintingStyle.stroke ..strokeWidth = 4);
        canvas.drawCircle(Offset.zero, rad * 2.3,
          Paint()..color = const Color(0xffffaa33).withValues(alpha: 0.40)
            ..style = PaintingStyle.stroke ..strokeWidth = 3);
        canvas.restore();
        canvas.drawCircle(pos, rad * 1.5, Paint()..color = tier.color.withValues(alpha: 0.18));
        canvas.drawCircle(pos, rad, Paint()..color = const Color(0xff000000));
        canvas.drawCircle(pos, rad, Paint()
          ..color = tier.color.withValues(alpha: 0.95)
          ..style = PaintingStyle.stroke ..strokeWidth = 2.5);
      } else {
        canvas.drawCircle(pos, rad * 1.7,
          Paint()..color = tier.color.withValues(alpha: done ? 0.28 : 0.16));
        canvas.drawCircle(pos, rad, Paint()
          ..color = tier.color.withValues(alpha: done ? 1.0 : 0.55));
        canvas.drawCircle(pos, rad, Paint()
          ..color = tier.color
          ..style = PaintingStyle.stroke ..strokeWidth = 2);
        canvas.drawCircle(pos - Offset(rad * 0.3, rad * 0.3), rad * 0.34,
          Paint()..color = Colors.white.withValues(alpha: done ? 0.5 : 0.25));
      }
    });

    // ── Hint markers (next-step nudge) ──────────────────────────────────────
    // Pulsing rings on the next correct cells; brightest for the immediate step,
    // fading along the short look-ahead.
    for (var i = 0; i < hintCells.length; i++) {
      final p = center(hintCells[i]);
      final a = (1.0 - i * 0.28).clamp(0.3, 1.0);
      canvas.drawCircle(p, cell * 0.30 + pulseV * 4, Paint()
        ..color = const Color(0xff9fe8ff).withValues(alpha: a * (0.35 + pulseV * 0.45))
        ..style = PaintingStyle.stroke ..strokeWidth = 2.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
      canvas.drawCircle(p, cell * 0.12,
        Paint()..color = const Color(0xffd8f4ff).withValues(alpha: a * 0.7));
    }

    // ── Black-hole "not yet" warning ────────────────────────────────────────
    // Expanding red ring when the player tries to enter the Black Hole before
    // the region is fully consumed (paired with the in-context hint text).
    if (nudge > 0 && nudgeKind == 1 && !collapsing) {
      canvas.drawCircle(bhCenter, cell * (0.55 + 0.5 * nudge),
        Paint()
          ..color = const Color(0xffff4466).withValues(alpha: (1 - nudge) * 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 + 2 * (1 - nudge));
    }

    // ── Head orb ──────────────────────────────────────────────────────────
    if (path.isNotEmpty) {
      final head = center(path.last);
      final prog = path.length / grid.cellCount;
      final hr   = cell * (0.15 + prog * 0.15) * (0.92 + pulseV * 0.12);
      canvas.drawCircle(head, hr * 2.4, Paint()..color = accent.withValues(alpha: 0.18));
      canvas.drawCircle(head, hr, Paint()..color = Colors.white.withValues(alpha: 0.92));
      canvas.drawCircle(head, hr, Paint()
        ..color = accent ..style = PaintingStyle.stroke ..strokeWidth = 2);
    }

    // ── Solution reveal ──────────────────────────────────────────────────────
    // The full solved worldline, drawn as a translucent cyan guide with a tracer
    // sweeping along it so the route order reads. Wormhole jumps lift the pen.
    if (showSolution && grid.solution.length >= 2) {
      final sol = grid.solution;
      final guide = Path()..moveTo(center(sol.first).dx, center(sol.first).dy);
      for (var i = 1; i < sol.length; i++) {
        if (grid.adjacent(sol[i - 1], sol[i])) {
          guide.lineTo(center(sol[i]).dx, center(sol[i]).dy);
        } else {
          guide.moveTo(center(sol[i]).dx, center(sol[i]).dy);
        }
      }
      canvas.drawPath(guide, Paint()
        ..color = _soln.withValues(alpha: 0.30)
        ..style = PaintingStyle.stroke ..strokeWidth = cell * 0.16
        ..strokeJoin = StrokeJoin.round ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
      canvas.drawPath(guide, Paint()
        ..color = _soln.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round ..strokeCap = StrokeCap.round);

      // Tracer dot sweeping the route to show direction/order.
      final fp = (traceT * (sol.length - 1)).clamp(0.0, (sol.length - 1).toDouble());
      final i0 = fp.floor(), i1 = (i0 + 1).clamp(0, sol.length - 1);
      final a = center(sol[i0]), b = center(sol[i1]);
      // Snap (don't interpolate) across a wormhole jump.
      final tp = grid.adjacent(sol[i0], sol[i1])
          ? Offset.lerp(a, b, fp - i0)! : a;
      canvas.drawCircle(tp, cell * 0.16,
        Paint()..color = _soln.withValues(alpha: 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      canvas.drawCircle(tp, cell * 0.09, Paint()..color = Colors.white);
    }

    // Outer border(s) — one per board in multiverse, tinted by universe (board 2
    // azure) so each board's identity reads at a glance.
    if (mv) {
      final boardW = layout!.boardW, boardH = layout.boardH;
      for (var b = 0; b < layout.origins.length; b++) {
        final o = layout.origins[b];
        final col = _universeColor(b);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(o.dx, o.dy, boardW, boardH), const Radius.circular(8)),
          Paint()..color = col.withValues(alpha: 0.55)
            ..style = PaintingStyle.stroke ..strokeWidth = 1.8);
      }
    } else {
      canvas.drawRRect(rrect!, Paint()
        ..color = accent.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke ..strokeWidth = 1.5);
    }

    // Close the Penrose tilt, then the collapse transform / fade layer.
    if (penrose)    canvas.restore();
    if (fadeLayer)  canvas.restore();
    if (collapsing) canvas.restore();

    // ── Collapse celebration (screen space, over the imploding region) ──────
    if (collapsing) _drawCollapse(canvas, size, pivot, solveT);
  }

  /// A deterministic field of distant stars revealed as the region zooms out —
  /// the "this region was one point in a galaxy" beat.
  /// A wormhole portal: swirling teal arcs round a dark core, brightening on warp.
  /// Stroke [path] as a dashed line (used for bridge connectors).
  void _dashedPath(Canvas canvas, Path path, Paint paint,
      {double dash = 7, double gap = 6}) {
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(
          metric.extractPath(d, min(d + dash, metric.length)), paint);
        d += dash + gap;
      }
    }
  }

  /// The enter-only mouth of a one-way bridge: a small dark well ringed in the
  /// destination universe's colour — deliberately unlike the finish black hole's
  /// big purple disk.
  void _drawBlackMouth(Canvas canvas, Offset p, double cell, {Color ring = _quantum}) {
    final r = cell * 0.26;
    canvas.drawCircle(p, r, Paint()..color = const Color(0xff09060f));
    canvas.drawCircle(p, r, Paint()
      ..color = ring.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke ..strokeWidth = 2.4);
  }

  /// The exit-only mouth of a one-way bridge: a radiant white hole ejecting rays.
  void _drawWhiteHole(Canvas canvas, Offset p, double cell, double pulseV) {
    final r = cell * 0.22;
    canvas.drawCircle(p, r * 2.0, Paint()
      ..color = _soln.withValues(alpha: 0.16 + pulseV * 0.10)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawCircle(p, r, Paint()..color = const Color(0xffeaffff));
    final ray = Paint()
      ..color = _soln.withValues(alpha: 0.7)
      ..strokeWidth = 2 ..strokeCap = StrokeCap.round;
    for (var k = 0; k < 8; k++) {
      final a = k * pi / 4, u = Offset(cos(a), sin(a));
      canvas.drawLine(p + u * (r * 1.2), p + u * (r * 1.9), ray);
    }
  }

  void _drawPortal(Canvas canvas, Offset pos, double cell, double pulseV,
      {Color color = _portal}) {
    final r    = cell * 0.34;
    final glow = (0.20 + warp * 0.55 + pulseV * 0.08).clamp(0.0, 1.0);
    canvas.drawCircle(pos, r * (1.5 + warp * 0.6),
      Paint()..color = color.withValues(alpha: glow));
    final rot = pulse * 2 * pi;
    for (var k = 0; k < 2; k++) {
      canvas.drawArc(
        Rect.fromCircle(center: pos, radius: r * (0.7 + k * 0.32)),
        rot * (k.isEven ? 1 : -1) + k * pi, pi * 1.2, false,
        Paint()
          ..color = color.withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round);
    }
    canvas.drawCircle(pos, r * 0.45, Paint()..color = const Color(0xff04141a));
    canvas.drawCircle(pos, r, Paint()
      ..color = color.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke ..strokeWidth = 2);
  }

  void _drawStarfield(Canvas canvas, Size size, double alpha) {
    if (alpha <= 0) return;
    final rnd  = Random(0x5EED);
    final twin = sin(pulse * 2 * pi);
    for (var i = 0; i < 80; i++) {
      final dx   = rnd.nextDouble() * size.width;
      final dy   = rnd.nextDouble() * size.height;
      final base = 0.25 + rnd.nextDouble() * 0.75;
      final r    = 0.5 + rnd.nextDouble() * 1.6;
      final tw   = 0.7 + 0.3 * sin(twin + i.toDouble());
      final col  = i.isEven ? Colors.white : const Color(0xff99eeff);
      canvas.drawCircle(Offset(dx, dy), r,
        Paint()..color = col.withValues(alpha: (base * tw * alpha).clamp(0.0, 1.0)));
    }
  }

  void _drawCollapse(Canvas canvas, Size size, Offset origin, double t) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size, const Radius.circular(10));

    // Flash — white burst peaking as the singularity ignites (~t=0.4).
    final flash = (1 - (t - 0.4).abs() / 0.14).clamp(0.0, 1.0) * 0.85;
    if (flash > 0) {
      canvas.drawRRect(rrect,
        Paint()..color = Colors.white.withValues(alpha: flash));
    }

    // Shockwave — two purple rings racing outward from the singularity.
    final sw = ((t - 0.4) / 0.6).clamp(0.0, 1.0);
    if (sw > 0) {
      for (final d in [0.0, 0.18]) {
        final p = (Curves.easeOut.transform((sw - d).clamp(0.0, 1.0)));
        if (p <= 0) continue;
        canvas.drawCircle(origin, size.width * (0.1 + 1.05 * p),
          Paint()
            ..color = const Color(0xffbb55ff).withValues(alpha: (1 - p) * 0.9)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2 + 12 * (1 - p)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
      }
    }

    // The new star — what the collapsed region becomes, lingering at the core.
    final starA = ((t - 0.55) / 0.15).clamp(0.0, 1.0)
                * (1 - ((t - 0.9) / 0.1).clamp(0.0, 1.0));
    if (starA > 0) {
      final pv = sin(pulse * 2 * pi) * 0.5 + 0.5;
      canvas.drawCircle(origin, 26 + pv * 6,
        Paint()..color = const Color(0xffbb55ff).withValues(alpha: starA * 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12));
      canvas.drawCircle(origin, 4 + pv * 1.5,
        Paint()..color = Colors.white.withValues(alpha: starA));
    }

    // Title.
    final textA = ((t - 0.5) / 0.15).clamp(0.0, 1.0)
                * (1 - ((t - 0.9) / 0.1).clamp(0.0, 1.0));
    if (textA > 0) {
      final c  = size.center(Offset.zero);
      final tp = TextPainter(textDirection: TextDirection.ltr)
        ..text = TextSpan(text: 'REGION\nCOLLAPSED', style: TextStyle(
          color: Colors.white.withValues(alpha: textA),
          fontSize: 22, fontFamily: 'monospace', fontWeight: FontWeight.bold,
          letterSpacing: 3, height: 1.3,
          shadows: const [Shadow(color: Color(0xffbb55ff), blurRadius: 18)]))
        ..textAlign = TextAlign.center
        ..layout(maxWidth: size.width);
      tp.paint(canvas, Offset(c.dx - tp.width / 2, c.dy - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_PuzzlePainter old) => true;
}
