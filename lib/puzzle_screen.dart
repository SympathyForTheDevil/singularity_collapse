import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'cosmic.dart';
import 'daily_service.dart';
import 'puzzle_model.dart';

enum PuzzleMode { daily, endless }

/// Singularity: Collapse — the standalone puzzle. Drag one worldline that
/// consumes cosmic objects in ascending order and fills every cell; reaching
/// the Black Hole (the final cell) collapses the region into a larger one.
class PuzzleScreen extends StatefulWidget {
  final PuzzleMode mode;
  const PuzzleScreen({super.key, this.mode = PuzzleMode.endless});
  @override
  State<PuzzleScreen> createState() => _PuzzleScreenState();
}

class _PuzzleScreenState extends State<PuzzleScreen>
    with TickerProviderStateMixin {
  late PuzzleGrid grid;
  final List<int> path = [];
  int  level      = 1;
  int  solvedCount = 0;
  bool solved     = false;
  bool _showShare = false;
  int  _streak    = 0;

  late final AnimationController _pulse;
  late final AnimationController _solve;

  double _boardSize = 320;

  static const Color _accent = Color(0xffffc24d);

  bool get _isDaily => widget.mode == PuzzleMode.daily;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
    _solve = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200))
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
    _pulse.dispose();
    _solve.dispose();
    super.dispose();
  }

  void _newPuzzle({bool advance = false}) {
    if (!_isDaily && advance) { level++; solvedCount++; }
    final rng = _isDaily ? Random(DailyService.todaySeed()) : null;
    final lvl = _isDaily ? DailyService.dailyLevel() : level;
    grid = PuzzleGrid.generate(lvl, rng: rng);
    path
      ..clear()
      ..add(grid.startCell);
    solved     = false;
    _showShare = false;
    setState(() {});
  }

  void _reset() {
    path
      ..clear()
      ..add(grid.startCell);
    setState(() {});
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

  void _onPan(Offset local) {
    if (solved) return;
    final cell = _cellAt(local);
    if (cell == null || cell == path.last) return;

    if (path.length >= 2 && cell == path[path.length - 2]) {
      path.removeLast();
      HapticFeedback.selectionClick();
      setState(() {});
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
    }
  }

  void _onSolved() {
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
    final now      = DateTime.now();
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
                      _isDaily
                        ? _iconBtn(Icons.arrow_back_ios_new,
                            () => Navigator.pop(context))
                        : _iconBtn(Icons.refresh, _reset),
                      const Spacer(),
                      Column(children: [
                        Text(
                          _isDaily
                            ? 'DAILY REGION  ·  $dateStr'
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
                      ]),
                      const Spacer(),
                      _isDaily
                        ? const SizedBox(width: 40)
                        : _iconBtn(Icons.add, () => _newPuzzle()),
                    ],
                  ),
                ),

                // Next-target hint
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 2),
                  child: Text(
                    solved ? 'REGION COLLAPSED' : 'NEXT  ·  ${nextTier.name.toUpperCase()}',
                    style: TextStyle(
                      color: solved ? Colors.white : nextTier.color,
                      fontSize: 10, fontFamily: 'monospace', letterSpacing: 3,
                      shadows: [Shadow(
                        color: nextTier.color.withValues(alpha: 0.5), blurRadius: 8)]),
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
                          onPanStart:  (d) => _onPan(d.localPosition),
                          onPanUpdate: (d) => _onPan(d.localPosition),
                          child: AnimatedBuilder(
                            animation: Listenable.merge([_pulse, _solve]),
                            builder: (_, _) => CustomPaint(
                              size: Size(side, side),
                              painter: _PuzzlePainter(
                                grid: grid,
                                path: path,
                                pulse: _pulse.value,
                                solveT: _solve.value,
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

            if (_streak > 0) ...[
              const SizedBox(height: 8),
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

            // Copy button
            _overlayBtn('COPY SHARE CARD', const Color(0xffffc24d), _copyShare),
            const SizedBox(height: 12),
            // Home button
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

  Widget _iconBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        color: const Color(0xff0a1018),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xff223344), width: 1),
      ),
      child: Icon(icon, color: const Color(0xff7799aa), size: 20),
    ),
  );
}

class _PuzzlePainter extends CustomPainter {
  final PuzzleGrid grid;
  final List<int>  path;
  final double     pulse;
  final double     solveT;
  final Color      accent;

  _PuzzlePainter({
    required this.grid,
    required this.path,
    required this.pulse,
    required this.solveT,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final n      = grid.size;
    final cell   = size.width / n;
    final pulseV = sin(pulse * 2 * pi) * 0.5 + 0.5;

    Offset center(int i) => Offset(
      (grid.colOf(i) + 0.5) * cell, (grid.rowOf(i) + 0.5) * cell);

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

    // ── Collapse celebration ───────────────────────────────────────────────
    if (solveT > 0) {
      final c     = size.center(Offset.zero);
      final ringR = size.width * 0.9 * Curves.easeOut.transform(solveT);
      canvas.drawCircle(c, ringR, Paint()
        ..color = const Color(0xffbb55ff).withValues(alpha: (1 - solveT) * 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6 + 10 * (1 - solveT));
      canvas.drawRRect(rrect, Paint()
        ..color = Colors.white.withValues(alpha: (1 - solveT) * 0.30));

      final tp = TextPainter(textDirection: TextDirection.ltr)
        ..text = TextSpan(text: 'REGION\nCOLLAPSED', style: TextStyle(
          color: Colors.white.withValues(alpha: (1 - solveT).clamp(0.0, 1.0)),
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
