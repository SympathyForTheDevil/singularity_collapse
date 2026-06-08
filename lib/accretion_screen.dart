import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'accretion_model.dart';
import 'audio.dart';
import 'cosmic.dart';

/// Accretion Cascade run screen (prototype + experiment harness). Drag one
/// worldline, absorb objects, reach the Black Hole to bank the score. The
/// cascade core and risk model are switchable live via the gear panel.
class AccretionScreen extends StatefulWidget {
  const AccretionScreen({super.key});
  @override
  State<AccretionScreen> createState() => _AccretionScreenState();
}

class _AccretionScreenState extends State<AccretionScreen>
    with TickerProviderStateMixin {
  late AccretionGame game;
  AccretionConfig _config = const AccretionConfig();

  int  _best       = 0;
  bool _muted      = AudioService.instance.muted;
  bool _showPanel  = false;
  bool _showOver   = false;
  double _boardSize = 320;

  late final AnimationController _pulse;
  late final AnimationController _collapse; // cash-out
  late final AnimationController _bust;     // bust flash
  late final AnimationController _pop;       // fusion pop on the multiplier

  static const Color _accent = Color(0xffffc24d);
  static const Color _purple = Color(0xffbb55ff);

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
    _collapse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2000))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) {
          setState(() => _showOver = true);
          _collapse.reset();
        }
      });
    _bust = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 700))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) {
          setState(() => _showOver = true);
          _bust.reset();
        }
      });
    _pop = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 360));
    game = AccretionGame(_config);
    _load();
    AudioService.instance.startAmbient();
  }

  @override
  void dispose() {
    AudioService.instance.stopAmbient();
    _pulse.dispose();
    _collapse.dispose();
    _bust.dispose();
    _pop.dispose();
    super.dispose();
  }

  // ── Persistence ────────────────────────────────────────────────────────────
  String get _bestKey => 'accr_best_${_config.core.index}_${_config.risk.index}';

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final core = CascadeCore.values[p.getInt('accr_core') ?? 0];
    final risk = RiskModel.values[p.getInt('accr_risk') ?? 0];
    if (mounted) {
      setState(() {
        _config = AccretionConfig(core: core, risk: risk);
        game.reset(config: _config);
        _best = p.getInt(_bestKey) ?? 0;
      });
    }
  }

  Future<void> _saveBest() async {
    if (game.finalScore <= _best) return;
    _best = game.finalScore;
    final p = await SharedPreferences.getInstance();
    await p.setInt(_bestKey, _best);
  }

  Future<void> _setConfig(AccretionConfig c) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('accr_core', c.core.index);
    await p.setInt('accr_risk', c.risk.index);
    setState(() {
      _config = c;
      _best = p.getInt(_bestKey) ?? 0;
      _showPanel = false;
      _showOver = false;
      game.reset(config: c);
    });
  }

  // ── Input ────────────────────────────────────────────────────────────────
  int? _cellAt(Offset pp) {
    final cs = _boardSize / game.size;
    if (pp.dx < 0 || pp.dy < 0 || pp.dx >= _boardSize || pp.dy >= _boardSize) {
      return null;
    }
    final c = (pp.dx / cs).floor().clamp(0, game.size - 1);
    final r = (pp.dy / cs).floor().clamp(0, game.size - 1);
    return r * game.size + c;
  }

  void _onPan(Offset local) {
    if (game.status != RunStatus.playing || _showOver || _showPanel) return;
    final cell = _cellAt(local);
    if (cell == null) return;
    if (game.path.isNotEmpty && cell == game.head) return;
    if (!game.canStep(cell)) return;
    final res = game.step(cell);
    _applyResult(res);
    setState(() {});
  }

  void _applyResult(StepResult res) {
    if (!res.moved) return;
    if (res.banked) {
      HapticFeedback.heavyImpact();
      AudioService.instance.collapse();
      _saveBest();
      _collapse.forward(from: 0);
      return;
    }
    if (res.absorbed) {
      if (res.fusions.isEmpty) {
        HapticFeedback.selectionClick();
        AudioService.instance.step(game.path.length / game.cellCount);
      } else {
        HapticFeedback.lightImpact();
        for (final t in res.fusions) {
          AudioService.instance.milestone(t); // pitched up the ladder
        }
        _pop.forward(from: 0);
      }
    }
    if (res.busted) {
      HapticFeedback.heavyImpact();
      AudioService.instance.denied();
      _saveBest();
      _bust.forward(from: 0);
    }
  }

  void _playAgain() {
    AudioService.instance.ui();
    setState(() { _showOver = false; game.reset(); });
  }

  Future<void> _toggleMute() async {
    await AudioService.instance.setMuted(!_muted);
    if (mounted) setState(() => _muted = AudioService.instance.muted);
    AudioService.instance.ui();
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff04050a),
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _topBar(),
                _hud(),
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
                            animation: Listenable.merge([_pulse, _collapse, _bust, _pop]),
                            builder: (_, _) => CustomPaint(
                              size: Size(side, side),
                              painter: _AccretionPainter(
                                game: game,
                                pulse: _pulse.value,
                                collapseT: _collapse.value,
                                bustT: _bust.value,
                                accent: _accent,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                _footer(),
              ],
            ),
          ),
          if (_showPanel) _buildPanel(),
          if (_showOver)  _buildRunOver(),
        ],
      ),
    );
  }

  Widget _topBar() => Padding(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
    child: SizedBox(
      height: 44,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 100),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('ACCRETION',
                      style: TextStyle(
                        color: _accent, fontSize: 18, fontFamily: 'monospace',
                        letterSpacing: 4, fontWeight: FontWeight.bold,
                        shadows: [Shadow(color: Color(0x66ffc24d), blurRadius: 14)])),
                    Text(
                      '${AccretionConfig.coreLabel(_config.core)} · ${AccretionConfig.riskLabel(_config.risk)}',
                      style: const TextStyle(
                        color: Color(0xff5e7a90), fontSize: 8,
                        fontFamily: 'monospace', letterSpacing: 1)),
                  ],
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: _iconBtn(Icons.home_outlined, () => Navigator.pop(context)),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _iconBtn(Icons.tune, () {
                  AudioService.instance.ui();
                  setState(() => _showPanel = true);
                }),
                const SizedBox(width: 8),
                _iconBtn(
                  _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  _toggleMute),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _hud() {
    final risk = switch (_config.risk) {
      RiskModel.stepBudget => 'STEPS  ${game.stepsLeft}',
      RiskModel.darkMatter => 'DARK  ${game.dark.length}',
      RiskModel.shrink     => 'REACH THE BLACK HOLE',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
      child: Column(
        children: [
          Text('${game.projectedScore}',
            style: const TextStyle(
              color: Colors.white, fontSize: 34, fontFamily: 'monospace',
              fontWeight: FontWeight.bold, letterSpacing: 2,
              shadows: [Shadow(color: Color(0x66ffc24d), blurRadius: 14)])),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _stat('MASS', '${game.mass}', const Color(0xff8aa6bc)),
              const SizedBox(width: 22),
              ScaleTransition(
                scale: Tween(begin: 1.0, end: 1.35).animate(
                  CurvedAnimation(parent: _pop, curve: Curves.easeOut)),
                child: _stat('MULT', '×${game.multiplier.toStringAsFixed(1)}', _accent),
              ),
              const SizedBox(width: 22),
              _stat('BEST', '$_best', _purple),
            ],
          ),
          const SizedBox(height: 8),
          Text(risk,
            style: const TextStyle(
              color: Color(0xff6fb0d0), fontSize: 11, fontFamily: 'monospace',
              letterSpacing: 2)),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(value,
        style: TextStyle(
          color: color, fontSize: 16, fontFamily: 'monospace',
          fontWeight: FontWeight.bold, letterSpacing: 1)),
      Text(label,
        style: const TextStyle(
          color: Color(0xff44607a), fontSize: 8, fontFamily: 'monospace',
          letterSpacing: 2)),
    ],
  );

  Widget _footer() => const Padding(
    padding: EdgeInsets.fromLTRB(24, 4, 24, 10),
    child: Text(
      'drag to absorb · fuse for combos · collapse on the black hole to bank',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Color(0xff3a526a), fontSize: 9.5,
        fontFamily: 'monospace', letterSpacing: 1, height: 1.5)),
  );

  // ── Run-over card ────────────────────────────────────────────────────────
  Widget _buildRunOver() {
    final banked = game.status == RunStatus.banked;
    return Positioned.fill(
      child: Container(
        color: const Color(0xee04050a),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(banked ? 'REGION COLLAPSED' : 'RUN ENDED',
                style: TextStyle(
                  color: Colors.white, fontSize: 22, fontFamily: 'monospace',
                  fontWeight: FontWeight.bold, letterSpacing: 4,
                  shadows: [Shadow(color: banked ? _purple : const Color(0xffff4466),
                    blurRadius: 20)])),
              const SizedBox(height: 6),
              Text(banked ? 'banked ×${game.multiplier.toStringAsFixed(1)}'
                          : 'multiplier lost',
                style: TextStyle(
                  color: banked ? _accent : const Color(0xffff4466),
                  fontSize: 11, fontFamily: 'monospace', letterSpacing: 2)),
              const SizedBox(height: 24),
              Text('${game.finalScore}',
                style: const TextStyle(
                  color: Colors.white, fontSize: 48, fontFamily: 'monospace',
                  fontWeight: FontWeight.bold)),
              Text(game.finalScore >= _best && game.finalScore > 0
                  ? 'NEW BEST' : 'BEST  $_best',
                style: const TextStyle(
                  color: _purple, fontSize: 11, fontFamily: 'monospace',
                  letterSpacing: 3)),
              const SizedBox(height: 32),
              _overlayBtn('PLAY AGAIN', _accent, _playAgain),
              const SizedBox(height: 12),
              _overlayBtn('CHANGE MODE', const Color(0xff7799aa),
                () => setState(() { _showOver = false; _showPanel = true; })),
              const SizedBox(height: 12),
              _overlayBtn('HOME', const Color(0xff7799aa),
                () => Navigator.pop(context)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Experiment panel ───────────────────────────────────────────────────────
  Widget _buildPanel() => Positioned.fill(
    child: Container(
      color: const Color(0xf204050a),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('EXPERIMENT',
              style: TextStyle(
                color: Colors.white, fontSize: 20, fontFamily: 'monospace',
                fontWeight: FontWeight.bold, letterSpacing: 4)),
            const SizedBox(height: 4),
            const Text('switch the mechanic, then play',
              style: TextStyle(
                color: Color(0xff6688aa), fontSize: 10, fontFamily: 'monospace',
                letterSpacing: 1)),
            const SizedBox(height: 28),
            const Text('CASCADE CORE',
              style: TextStyle(color: _accent, fontSize: 11,
                fontFamily: 'monospace', letterSpacing: 3)),
            const SizedBox(height: 10),
            for (final c in CascadeCore.values)
              _panelRow(AccretionConfig.coreLabel(c), _config.core == c,
                () => _setConfig(_config.copyWith(core: c))),
            const SizedBox(height: 24),
            const Text('RISK MODEL',
              style: TextStyle(color: _accent, fontSize: 11,
                fontFamily: 'monospace', letterSpacing: 3)),
            const SizedBox(height: 10),
            for (final r in RiskModel.values)
              _panelRow(AccretionConfig.riskLabel(r), _config.risk == r,
                () => _setConfig(_config.copyWith(risk: r))),
            const SizedBox(height: 28),
            _overlayBtn('CLOSE', const Color(0xff7799aa),
              () => setState(() => _showPanel = false)),
          ],
        ),
      ),
    ),
  );

  Widget _panelRow(String label, bool active, VoidCallback onTap) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        width: 230,
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
        decoration: BoxDecoration(
          color: active ? const Color(0xff14202c) : const Color(0xff0a1018),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? _accent : const Color(0xff223344),
            width: active ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Icon(active ? Icons.radio_button_checked : Icons.radio_button_off,
              color: active ? _accent : const Color(0xff44607a), size: 16),
            const SizedBox(width: 12),
            Text(label,
              style: TextStyle(
                color: active ? Colors.white : const Color(0xff7799aa),
                fontSize: 13, fontFamily: 'monospace',
                fontWeight: FontWeight.bold, letterSpacing: 2)),
          ],
        ),
      ),
    );

  Widget _overlayBtn(String label, Color color, VoidCallback onTap) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 56),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 40),
        decoration: BoxDecoration(
          color: const Color(0xff0a1018),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.55), width: 1.5),
        ),
        child: Text(label,
          style: TextStyle(
            color: color, fontSize: 12, fontFamily: 'monospace',
            fontWeight: FontWeight.bold, letterSpacing: 2,
            shadows: [Shadow(color: color.withValues(alpha: 0.35), blurRadius: 8)])),
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

class _AccretionPainter extends CustomPainter {
  final AccretionGame game;
  final double pulse;
  final double collapseT;  // 0→1 cash-out
  final double bustT;      // 0→1 bust flash
  final Color  accent;

  _AccretionPainter({
    required this.game,
    required this.pulse,
    required this.collapseT,
    required this.bustT,
    required this.accent,
  });

  Color _tierColor(int tier) =>
      kLowerTiers[(tier - 1).clamp(0, kLowerTiers.length - 1)].color;

  double _collapseScale(double t) {
    if (t < 0.35) return 1.0 - 0.16 * Curves.easeIn.transform(t / 0.35);
    if (t < 0.45) return 0.84;
    return 0.84 * (1 - Curves.easeInCubic.transform((t - 0.45) / 0.55));
  }

  double _contentAlpha(double t) =>
      t <= 0.5 ? 1.0 : (1 - (t - 0.5) / 0.35).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final n      = game.size;
    final cell   = size.width / n;
    final pulseV = sin(pulse * 2 * pi) * 0.5 + 0.5;
    Offset center(int i) =>
        Offset((game.colOf(i) + 0.5) * cell, (game.rowOf(i) + 0.5) * cell);

    final bounds = Offset.zero & size;
    final bh     = game.blackHoleCell >= 0 ? center(game.blackHoleCell) : size.center(Offset.zero);

    final collapsing   = collapseT > 0;
    final contentAlpha = _contentAlpha(collapseT);
    if (collapsing) {
      _drawStarfield(canvas, size, ((collapseT - 0.4) / 0.3).clamp(0.0, 1.0));
      final s = _collapseScale(collapseT);
      canvas.save();
      canvas.translate(bh.dx, bh.dy);
      canvas.scale(s);
      canvas.translate(-bh.dx, -bh.dy);
    }
    final fadeLayer = collapsing && contentAlpha < 0.99;
    if (fadeLayer) {
      canvas.saveLayer(bounds,
        Paint()..color = Colors.white.withValues(alpha: contentAlpha));
    }

    // Backdrop + faint grid
    final rrect = RRect.fromRectAndRadius(bounds, const Radius.circular(10));
    canvas.drawRRect(rrect, Paint()..color = const Color(0xff070b12));
    final gridPaint = Paint()
      ..color = const Color(0xff111c2a)..style = PaintingStyle.stroke..strokeWidth = 1;
    for (var i = 0; i <= n; i++) {
      canvas.drawLine(Offset(i * cell, 0), Offset(i * cell, size.height), gridPaint);
      canvas.drawLine(Offset(0, i * cell), Offset(size.width, i * cell), gridPaint);
    }

    final visited = game.path.toSet();

    // Cells
    for (var i = 0; i < game.cellCount; i++) {
      final code = game.cells[i];
      final pos  = center(i);
      if (code == AccretionGame.kBlackHole) {
        _drawBlackHole(canvas, pos, cell, pulseV);
      } else if (code == AccretionGame.kDark) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: pos, width: cell * 0.82, height: cell * 0.82),
            const Radius.circular(6)),
          Paint()..color = const Color(0xff2a1438));
        canvas.drawCircle(pos, cell * 0.18,
          Paint()..color = const Color(0xff5a2a78).withValues(alpha: 0.6));
      } else if (code >= 1) {
        final done = visited.contains(i);
        final col  = _tierColor(code);
        final rad  = cell * (0.15 + code * 0.045);
        final a    = done ? 0.22 : 1.0;
        canvas.drawCircle(pos, rad * 1.7,
          Paint()..color = col.withValues(alpha: (done ? 0.06 : 0.16)));
        canvas.drawCircle(pos, rad, Paint()..color = col.withValues(alpha: a * 0.85));
        canvas.drawCircle(pos, rad, Paint()
          ..color = col.withValues(alpha: a)..style = PaintingStyle.stroke..strokeWidth = 2);
        if (!done) {
          canvas.drawCircle(pos - Offset(rad * 0.3, rad * 0.3), rad * 0.32,
            Paint()..color = Colors.white.withValues(alpha: 0.35));
        }
      }
    }

    // Worldline
    if (game.path.length >= 2) {
      final line = Path()..moveTo(center(game.path.first).dx, center(game.path.first).dy);
      for (var i = 1; i < game.path.length; i++) {
        line.lineTo(center(game.path[i]).dx, center(game.path[i]).dy);
      }
      canvas.drawPath(line, Paint()
        ..color = accent.withValues(alpha: 0.26)..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.5..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      canvas.drawPath(line, Paint()
        ..color = accent..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.24..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round);
    }

    // Head
    if (game.path.isNotEmpty) {
      final h  = center(game.head);
      final hr = cell * 0.2 * (0.92 + pulseV * 0.12);
      canvas.drawCircle(h, hr * 2.4, Paint()..color = accent.withValues(alpha: 0.18));
      canvas.drawCircle(h, hr, Paint()..color = Colors.white.withValues(alpha: 0.92));
      canvas.drawCircle(h, hr, Paint()
        ..color = accent..style = PaintingStyle.stroke..strokeWidth = 2);
    }

    canvas.drawRRect(rrect, Paint()
      ..color = accent.withValues(alpha: 0.45)..style = PaintingStyle.stroke..strokeWidth = 1.5);

    if (fadeLayer)  canvas.restore();
    if (collapsing) canvas.restore();

    if (collapsing) _drawCollapse(canvas, size, bh, collapseT);

    // Bust flash — red vignette
    if (bustT > 0) {
      final a = (1 - bustT) * 0.5;
      canvas.drawRRect(rrect, Paint()
        ..color = const Color(0xffff4466).withValues(alpha: a));
    }
  }

  void _drawBlackHole(Canvas canvas, Offset pos, double cell, double pulseV) {
    final rad = cell * 0.30;
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.scale(1.0, 0.34);
    canvas.drawCircle(Offset.zero, rad * 1.7,
      Paint()..color = const Color(0xffff7722).withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke..strokeWidth = 4);
    canvas.drawCircle(Offset.zero, rad * 2.3,
      Paint()..color = const Color(0xffffaa33).withValues(alpha: 0.40)
        ..style = PaintingStyle.stroke..strokeWidth = 3);
    canvas.restore();
    canvas.drawCircle(pos, rad * 1.5 + pulseV * 3,
      Paint()..color = const Color(0xffbb55ff).withValues(alpha: 0.18));
    canvas.drawCircle(pos, rad, Paint()..color = const Color(0xff000000));
    canvas.drawCircle(pos, rad, Paint()
      ..color = const Color(0xffbb55ff).withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke..strokeWidth = 2.5);
  }

  void _drawStarfield(Canvas canvas, Size size, double alpha) {
    if (alpha <= 0) return;
    final rnd  = Random(0x5EED);
    final twin = sin(pulse * 2 * pi);
    for (var i = 0; i < 80; i++) {
      final dx = rnd.nextDouble() * size.width;
      final dy = rnd.nextDouble() * size.height;
      final base = 0.25 + rnd.nextDouble() * 0.75;
      final r  = 0.5 + rnd.nextDouble() * 1.6;
      final tw = 0.7 + 0.3 * sin(twin + i.toDouble());
      final col = i.isEven ? Colors.white : const Color(0xff99eeff);
      canvas.drawCircle(Offset(dx, dy), r,
        Paint()..color = col.withValues(alpha: (base * tw * alpha).clamp(0.0, 1.0)));
    }
  }

  void _drawCollapse(Canvas canvas, Size size, Offset origin, double t) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10));
    final flash = (1 - (t - 0.4).abs() / 0.14).clamp(0.0, 1.0) * 0.85;
    if (flash > 0) {
      canvas.drawRRect(rrect, Paint()..color = Colors.white.withValues(alpha: flash));
    }
    final sw = ((t - 0.4) / 0.6).clamp(0.0, 1.0);
    if (sw > 0) {
      for (final d in [0.0, 0.18]) {
        final p = Curves.easeOut.transform((sw - d).clamp(0.0, 1.0));
        if (p <= 0) continue;
        canvas.drawCircle(origin, size.width * (0.1 + 1.05 * p),
          Paint()
            ..color = const Color(0xffbb55ff).withValues(alpha: (1 - p) * 0.9)
            ..style = PaintingStyle.stroke..strokeWidth = 2 + 12 * (1 - p)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
      }
    }
    final textA = ((t - 0.5) / 0.15).clamp(0.0, 1.0) * (1 - ((t - 0.9) / 0.1).clamp(0.0, 1.0));
    if (textA > 0) {
      final c = size.center(Offset.zero);
      final tp = TextPainter(textDirection: TextDirection.ltr)
        ..text = TextSpan(text: 'COLLAPSE', style: TextStyle(
          color: Colors.white.withValues(alpha: textA),
          fontSize: 24, fontFamily: 'monospace', fontWeight: FontWeight.bold,
          letterSpacing: 4,
          shadows: const [Shadow(color: Color(0xffbb55ff), blurRadius: 18)]))
        ..textAlign = TextAlign.center
        ..layout(maxWidth: size.width);
      tp.paint(canvas, Offset(c.dx - tp.width / 2, c.dy - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_AccretionPainter old) => true;
}
