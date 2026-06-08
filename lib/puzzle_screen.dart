import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'cosmic.dart';
import 'puzzle_model.dart';

/// Singularity: Collapse — the standalone puzzle. Drag one worldline that
/// consumes cosmic objects in ascending order and fills every cell; reaching
/// the Black Hole (the final cell) collapses the region into a larger one.
class PuzzleScreen extends StatefulWidget {
  const PuzzleScreen({super.key});
  @override
  State<PuzzleScreen> createState() => _PuzzleScreenState();
}

class _PuzzleScreenState extends State<PuzzleScreen>
    with TickerProviderStateMixin {
  late PuzzleGrid grid;
  final List<int> path = [];
  int  level   = 1;
  int  solvedCount = 0;
  bool solved  = false;

  late final AnimationController _pulse;
  late final AnimationController _solve;

  double _boardSize = 320;

  static const Color _accent = Color(0xffffc24d); // worldline (gold)

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
    _solve = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) {
          _newPuzzle(advance: true);
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
    if (advance) { level++; solvedCount++; }
    grid = PuzzleGrid.generate(level);
    path
      ..clear()
      ..add(grid.startCell);
    solved = false;
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
      if (m != _milestonesVisited() + 1) return false; // must consume in order
      // The Black Hole is the finish: only enterable as the very last cell, so
      // reaching it requires the whole region to be consumed first.
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

    // Drag back onto the previous cell to undo the last step.
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

  @override
  Widget build(BuildContext context) {
    final filled = path.length;
    final total  = grid.cellCount;
    final nextTier = tierFor(
        (_milestonesVisited() + 1).clamp(1, grid.milestoneCount),
        grid.milestoneCount);
    return Scaffold(
      backgroundColor: const Color(0xff04050a),
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
              child: Row(
                children: [
                  _iconBtn(Icons.refresh, _reset),
                  const Spacer(),
                  Column(children: [
                    Text('COLLAPSE  ·  STAGE $level',
                      style: const TextStyle(color: _accent, fontSize: 15,
                        fontFamily: 'monospace', letterSpacing: 3,
                        fontWeight: FontWeight.bold,
                        shadows: [Shadow(color: Color(0x66ffc24d), blurRadius: 12)])),
                    const SizedBox(height: 2),
                    Text('$filled / $total  CONSUMED   ·   SOLVED  $solvedCount',
                      style: const TextStyle(color: Color(0xff44607a), fontSize: 9,
                        fontFamily: 'monospace', letterSpacing: 2)),
                  ]),
                  const Spacer(),
                  _iconBtn(Icons.add, () => _newPuzzle()),
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
                  shadows: [Shadow(color: nextTier.color.withValues(alpha: 0.5), blurRadius: 8)]),
              ),
            ),

            // ── Board ────────────────────────────────────────────────────────
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
                        builder: (_, __) => CustomPaint(
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

            // ── Footer ───────────────────────────────────────────────────────
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 6, 24, 10),
              child: Text(
                'Drag one path · consume objects in order · fill every cell · finish on the black hole',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xff3a526a), fontSize: 9.5,
                  fontFamily: 'monospace', letterSpacing: 1, height: 1.5)),
            ),
          ],
        ),
      ),
    );
  }

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
  final double     pulse;   // 0..1 repeating
  final double     solveT;  // 0..1 during collapse celebration
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

    // ── Worldline ─────────────────────────────────────────────────────────────
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

    // ── Cosmic milestones ─────────────────────────────────────────────────────
    final visited = path.where((c) => grid.milestones.containsKey(c)).length;
    final count = grid.milestoneCount;
    grid.milestones.forEach((cellIdx, mnum) {
      final pos  = center(cellIdx);
      final tier = tierFor(mnum, count);
      final done = mnum <= visited;
      final next = mnum == visited + 1;
      // Ascending size: small objects → big black hole.
      final frac = count > 1 ? (mnum - 1) / (count - 1) : 0.0;
      final rad  = cell * (0.20 + frac * 0.14);

      if (next) {
        canvas.drawCircle(pos, rad + 5 + pulseV * 3,
          Paint()..color = tier.color.withValues(alpha: 0.30));
      }

      if (tier.isBlackHole) {
        // Accretion disk
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
        // Void + ring + glow
        canvas.drawCircle(pos, rad * 1.5, Paint()..color = tier.color.withValues(alpha: 0.18));
        canvas.drawCircle(pos, rad, Paint()..color = const Color(0xff000000));
        canvas.drawCircle(pos, rad, Paint()
          ..color = tier.color.withValues(alpha: 0.95)
          ..style = PaintingStyle.stroke ..strokeWidth = 2.5);
      } else {
        // Glowing orb
        canvas.drawCircle(pos, rad * 1.7,
          Paint()..color = tier.color.withValues(alpha: done ? 0.28 : 0.16));
        canvas.drawCircle(pos, rad, Paint()
          ..color = tier.color.withValues(alpha: done ? 1.0 : 0.55));
        canvas.drawCircle(pos, rad, Paint()
          ..color = tier.color
          ..style = PaintingStyle.stroke ..strokeWidth = 2);
        // Highlight
        canvas.drawCircle(pos - Offset(rad * 0.3, rad * 0.3), rad * 0.34,
          Paint()..color = Colors.white.withValues(alpha: done ? 0.5 : 0.25));
      }
    });

    // ── Head orb (the singularity), grows with progress ───────────────────────
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

    // ── Collapse celebration ──────────────────────────────────────────────────
    if (solveT > 0) {
      final c = size.center(Offset.zero);
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
