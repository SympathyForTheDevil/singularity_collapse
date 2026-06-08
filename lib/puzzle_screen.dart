import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'cosmic.dart';
import 'daily_service.dart';
import 'puzzle_model.dart';

enum PuzzleMode { daily, infinity, zen }

/// Singularity: Collapse — the standalone puzzle. Drag one worldline that
/// consumes cosmic objects in ascending order and fills every cell; reaching
/// the Black Hole (the final cell) collapses the region into a larger one.
class PuzzleScreen extends StatefulWidget {
  final PuzzleMode mode;
  const PuzzleScreen({super.key, this.mode = PuzzleMode.infinity});
  @override
  State<PuzzleScreen> createState() => _PuzzleScreenState();
}

class _PuzzleScreenState extends State<PuzzleScreen>
    with TickerProviderStateMixin {
  late PuzzleGrid grid;
  final List<int> path = [];
  int  level       = 1;
  int  solvedCount = 0;
  bool solved      = false;
  bool _showShare  = false;
  int  _streak     = 0;

  // Timer
  int    _seconds = 0;
  Timer? _timer;

  late final AnimationController _pulse;
  late final AnimationController _solve;
  late final AnimationController _nudge;   // black-hole "not yet" warning flash

  // Transient in-context hint shown in the NEXT line (e.g. why a move was blocked).
  String?  _hint;
  Timer?   _hintTimer;
  int      _lastNudgeMs = 0;               // throttle the black-hole nudge

  double _boardSize = 320;

  static const Color _accent = Color(0xffffc24d);

  bool get _isDaily => widget.mode == PuzzleMode.daily;
  bool get _isZen   => widget.mode == PuzzleMode.zen;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
    _nudge = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600));
    _solve = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2000))
      ..addStatusListener((s) async {
        if (s == AnimationStatus.completed && mounted) {
          if (_isDaily) {
            final streak = await DailyService.markSolvedAndGetStreak();
            if (mounted) setState(() { _streak = streak; _showShare = true; });
          } else {
            _newPuzzle(advance: true);
          }
          _solve.reset();
        }
      });
    _newPuzzle();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _hintTimer?.cancel();
    _pulse.dispose();
    _solve.dispose();
    _nudge.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _seconds = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !solved) setState(() => _seconds++);
    });
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
    final lvl = _isDaily ? DailyService.dailyLevel() : level;
    grid = PuzzleGrid.generate(lvl, rng: rng);
    path
      ..clear()
      ..add(grid.startCell);
    solved     = false;
    _showShare = false;
    _clearHint();
    _nudge.reset();
    _startTimer();
    setState(() {});
  }

  void _reset() {
    if (solved) return;
    path
      ..clear()
      ..add(grid.startCell);
    _clearHint();
    HapticFeedback.mediumImpact();
    setState(() {});
  }

  /// Step back one cell (undo the last move).
  void _undo() {
    if (solved || path.length < 2) return;
    path.removeLast();
    _clearHint();
    HapticFeedback.selectionClick();
    setState(() {});
  }

  /// Truncate the worldline back to [cell] (drops everything after it). Tapping
  /// any visited cell rewinds to there — the fast way to fix an early mistake.
  void _truncateTo(int cell) {
    if (solved) return;
    final i = path.indexOf(cell);
    if (i < 0 || i == path.length - 1) return;
    path.removeRange(i + 1, path.length);
    _clearHint();
    HapticFeedback.selectionClick();
    setState(() {});
  }

  void _showHint(String text) {
    _hintTimer?.cancel();
    setState(() => _hint = text);
    _hintTimer = Timer(const Duration(milliseconds: 1600), () {
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
    return path.length != grid.cellCount - 1;
  }

  void _nudgeBlackHole() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastNudgeMs < 700) return;   // throttle repeated bumps
    _lastNudgeMs = now;
    HapticFeedback.heavyImpact();
    _nudge.forward(from: 0);
    _showHint('CONSUME EVERY CELL FIRST');
  }

  int _milestonesVisited() =>
      path.where((c) => grid.milestones.containsKey(c)).length;

  bool _canStep(int target) {
    final head = path.last;
    if (!grid.adjacent(head, target)) return false;
    if (grid.hasWall(head, target))   return false;
    if (path.contains(target))        return false;
    final m = grid.milestones[target];
    if (m != null) {
      if (m != _milestonesVisited() + 1) return false;
      if (m == grid.milestoneCount && path.length != grid.cellCount - 1) {
        return false;
      }
    }
    return true;
  }

  int? _cellAt(Offset p) {
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
    final cs = _boardSize / grid.size;
    final fx = p.dx / cs - grid.colOf(cell);
    final fy = p.dy / cs - grid.rowOf(cell);
    return fx > _undoMargin && fx < 1 - _undoMargin &&
           fy > _undoMargin && fy < 1 - _undoMargin;
  }

  void _onPan(Offset local) {
    if (solved) return;
    final cell = _cellAt(local);
    if (cell == null || cell == path.last) return;

    if (path.length >= 2 && cell == path[path.length - 2]) {
      // Deliberate pull-back into the previous cell = undo; a mere edge graze
      // during forward motion is ignored.
      if (_deepInside(local, cell)) {
        path.removeLast();
        _clearHint();
        HapticFeedback.selectionClick();
        setState(() {});
      }
      return;
    }

    if (_canStep(cell)) {
      final isMs = grid.milestones.containsKey(cell);
      path.add(cell);
      HapticFeedback.lightImpact();
      if (isMs && grid.milestones[cell] != grid.milestoneCount) {
        HapticFeedback.selectionClick();
      }
      if (path.length == grid.cellCount) _onSolved();
      setState(() {});
    } else if (_isBlackHoleEarly(cell)) {
      _nudgeBlackHole();   // explain the block instead of silently rejecting it
    }
  }

  /// Tap a visited cell to rewind the worldline to it. Tapping elsewhere does nothing.
  void _onTap(Offset local) {
    if (solved) return;
    final cell = _cellAt(local);
    if (cell == null) return;
    if (path.contains(cell)) _truncateTo(cell);
  }

  void _onSolved() {
    _stopTimer();
    solved = true;
    HapticFeedback.heavyImpact();
    _solve.forward(from: 0);
  }

  String _buildShareText() {
    final today   = DailyService.todayStr();
    final pathSet = path.toSet();
    final buf     = StringBuffer()
      ..writeln('Singularity: Collapse')
      ..writeln('Daily Region $today ✅');
    if (!_isZen) buf.writeln('Time: ${_formatTime(_seconds)}');
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
    final total    = grid.cellCount;
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
                // ── Top bar ────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
                  child: Row(
                    children: [
                      // Left: back to menu / home
                      _iconBtn(
                        _isDaily ? Icons.arrow_back_ios_new : Icons.home_outlined,
                        () => Navigator.pop(context)),

                      const Spacer(),

                      // Centre: title + stats + timer
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _isDaily ? 'DAILY REGION  ·  $dateStr'
                              : _isZen ? 'ZEN  ·  STAGE $level'
                              : 'COLLAPSE  ·  STAGE $level',
                            style: const TextStyle(
                              color: _accent, fontSize: 15,
                              fontFamily: 'monospace', letterSpacing: 3,
                              fontWeight: FontWeight.bold,
                              shadows: [Shadow(color: Color(0x66ffc24d), blurRadius: 12)])),
                          const SizedBox(height: 2),
                          Text(
                            _isDaily
                              ? '$filled / $total  CONSUMED'
                              : '$filled / $total  CONSUMED   ·   SOLVED  $solvedCount',
                            style: const TextStyle(
                              color: Color(0xff44607a), fontSize: 9,
                              fontFamily: 'monospace', letterSpacing: 2)),
                        ],
                      ),

                      const Spacer(),

                      // Right: path controls — undo one step, reset to start
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _iconBtn(Icons.undo, _undo,
                            enabled: !solved && path.length > 1),
                          const SizedBox(width: 8),
                          _iconBtn(Icons.refresh, _reset,
                            enabled: !solved && path.length > 1),
                        ],
                      ),
                    ],
                  ),
                ),

                // Timer — full-width row, prominent; hidden in zen mode
                if (!_isZen)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 2),
                    child: Text(
                      _formatTime(_seconds),
                      style: const TextStyle(
                        color: Color(0xff5599bb),
                        fontSize: 26,
                        fontFamily: 'monospace',
                        letterSpacing: 6,
                        fontWeight: FontWeight.w300,
                        shadows: [Shadow(color: Color(0x445599bb), blurRadius: 12)]),
                    ),
                  ),

                // Next-target hint — also surfaces transient rule hints (e.g.
                // why the Black Hole can't be entered yet).
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 2),
                  child: Text(
                    _hint != null
                      ? _hint!
                      : solved
                        ? 'REGION COLLAPSED'
                        : 'NEXT  ·  ${nextTier.name.toUpperCase()}',
                    style: TextStyle(
                      color: _hint != null
                        ? const Color(0xffff4466)
                        : solved ? Colors.white : nextTier.color,
                      fontSize: 10, fontFamily: 'monospace', letterSpacing: 3,
                      shadows: [Shadow(
                        color: (_hint != null
                            ? const Color(0xffff4466)
                            : nextTier.color).withValues(alpha: 0.5),
                        blurRadius: 8)]),
                  ),
                ),

                // ── Board ──────────────────────────────────────────────────
                Expanded(
                  child: Center(
                    child: LayoutBuilder(
                      builder: (ctx, cons) {
                        final side = (min(cons.maxWidth, cons.maxHeight) - 16)
                            .clamp(200.0, 620.0);
                        _boardSize = side;
                        return GestureDetector(
                          onTapUp:     (d) => _onTap(d.localPosition),
                          onPanStart:  (d) => _onPan(d.localPosition),
                          onPanUpdate: (d) => _onPan(d.localPosition),
                          child: AnimatedBuilder(
                            animation: Listenable.merge([_pulse, _solve, _nudge]),
                            builder: (_, _) => CustomPaint(
                              size: Size(side, side),
                              painter: _PuzzlePainter(
                                grid: grid,
                                path: path,
                                pulse: _pulse.value,
                                solveT: _solve.value,
                                nudge: _nudge.value,
                                accent: _accent,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),

                // ── Footer ─────────────────────────────────────────────────
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 6, 24, 10),
                  child: Text(
                    'Drag one path · consume objects in order · fill every cell · finish on the black hole',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xff3a526a), fontSize: 9.5,
                      fontFamily: 'monospace', letterSpacing: 1, height: 1.5)),
                ),
              ],
            ),
          ),

          // ── Share overlay (daily mode, after solve) ─────────────────────
          if (_showShare) _buildShareOverlay(),
        ],
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

            if (!_isZen && _seconds > 0) ...[
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
}

class _PuzzlePainter extends CustomPainter {
  final PuzzleGrid grid;
  final List<int>  path;
  final double     pulse;
  final double     solveT;   // 0 → 1 collapse celebration
  final double     nudge;    // 0 → 1 black-hole "not yet" warning flash
  final Color      accent;

  _PuzzlePainter({
    required this.grid,
    required this.path,
    required this.pulse,
    required this.solveT,
    required this.nudge,
    required this.accent,
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
    final n      = grid.size;
    final cell   = size.width / n;
    final pulseV = sin(pulse * 2 * pi) * 0.5 + 0.5;

    Offset center(int i) => Offset(
      (grid.colOf(i) + 0.5) * cell, (grid.rowOf(i) + 0.5) * cell);

    final bounds   = Offset.zero & size;
    final bhCenter = center(grid.blackHoleCell);

    // During the collapse: reveal a starfield behind the board, then scale all
    // board content down toward the black hole (the region implodes into a
    // single point of a wider galaxy). A fade layer dissolves the old region.
    final collapsing   = solveT > 0;
    final contentAlpha = _contentAlpha(solveT);
    if (collapsing) {
      _drawStarfield(canvas, size, ((solveT - 0.4) / 0.3).clamp(0.0, 1.0));
      final s = _collapseScale(solveT);
      canvas.save();
      canvas.translate(bhCenter.dx, bhCenter.dy);
      canvas.scale(s);
      canvas.translate(-bhCenter.dx, -bhCenter.dy);
    }
    final fadeLayer = collapsing && contentAlpha < 0.99;
    if (fadeLayer) {
      canvas.saveLayer(bounds,
        Paint()..color = Colors.white.withValues(alpha: contentAlpha));
    }

    // Board backdrop
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size, const Radius.circular(10));
    canvas.drawRRect(rrect, Paint()..color = const Color(0xff070b12));

    // Faint cell grid
    final gridPaint = Paint()
      ..color = const Color(0xff142030)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i <= n; i++) {
      canvas.drawLine(Offset(i * cell, 0), Offset(i * cell, size.height), gridPaint);
      canvas.drawLine(Offset(0, i * cell), Offset(size.width, i * cell), gridPaint);
    }

    // Filled-cell tint
    final fillPaint = Paint()..color = accent.withValues(alpha: 0.10);
    for (final c in path) {
      final r = grid.rowOf(c), col = grid.colOf(c);
      canvas.drawRect(
        Rect.fromLTWH(col * cell + 1.5, r * cell + 1.5, cell - 3, cell - 3),
        fillPaint);
    }

    // Walls
    final wallPaint = Paint()
      ..color = const Color(0xff5a6e84)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    final cc = grid.cellCount;
    for (final key in grid.walls) {
      final lo = key ~/ cc, hi = key % cc;
      if (hi - lo == 1 && grid.rowOf(lo) == grid.rowOf(hi)) {
        final x = grid.colOf(hi) * cell;
        final y = grid.rowOf(lo) * cell;
        canvas.drawLine(Offset(x, y + 2), Offset(x, y + cell - 2), wallPaint);
      } else if (hi - lo == n) {
        final y = grid.rowOf(hi) * cell;
        final x = grid.colOf(lo) * cell;
        canvas.drawLine(Offset(x + 2, y), Offset(x + cell - 2, y), wallPaint);
      }
    }

    // ── Worldline ──────────────────────────────────────────────────────────
    if (path.length >= 2) {
      final line = Path()..moveTo(center(path.first).dx, center(path.first).dy);
      for (var i = 1; i < path.length; i++) {
        line.lineTo(center(path[i]).dx, center(path[i]).dy);
      }
      canvas.drawPath(line, Paint()
        ..color = accent.withValues(alpha: 0.26)
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.60
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      canvas.drawPath(line, Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.28
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round);
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
        canvas.drawCircle(pos, rad + 5 + pulseV * 3,
          Paint()..color = tier.color.withValues(alpha: 0.30));
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

    // ── Black-hole "not yet" warning ────────────────────────────────────────
    // Expanding red ring when the player tries to enter the Black Hole before
    // the region is fully consumed (paired with the in-context hint text).
    if (nudge > 0 && !collapsing) {
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

    // Outer border
    canvas.drawRRect(rrect, Paint()
      ..color = accent.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke ..strokeWidth = 1.5);

    // Close the collapse transform / fade layer.
    if (fadeLayer)  canvas.restore();
    if (collapsing) canvas.restore();

    // ── Collapse celebration (screen space, over the imploding region) ──────
    if (collapsing) _drawCollapse(canvas, size, bhCenter, solveT);
  }

  /// A deterministic field of distant stars revealed as the region zooms out —
  /// the "this region was one point in a galaxy" beat.
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
