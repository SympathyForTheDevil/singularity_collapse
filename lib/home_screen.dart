import 'dart:math';
import 'package:flutter/material.dart';
import 'audio.dart';
import 'daily_service.dart';
import 'field_guide.dart';
import 'puzzle_model.dart';
import 'puzzle_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  bool _solvedToday = false;
  int  _streak      = 0;
  bool _loaded      = false;
  bool _muted       = AudioService.instance.muted;
  bool _showDev     = false;

  late final AnimationController _pulse;

  static const Color _gold   = Color(0xffffc24d);
  static const Color _purple = Color(0xffbb55ff);
  static const Color _cyan   = Color(0xff99eeff);

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2000))..repeat();
    _load();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final solved = await DailyService.isSolvedToday();
    final streak = await DailyService.getStreak();
    if (mounted) {
      setState(() { _solvedToday = solved; _streak = streak; _loaded = true; });
    }
  }

  Future<void> _goDaily() async {
    AudioService.instance.ui();
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => const PuzzleScreen(mode: PuzzleMode.daily)));
    _load();
  }

  void _goInfinity() {
    AudioService.instance.ui();
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => const PuzzleScreen(mode: PuzzleMode.infinity)));
  }

  void _goZen() {
    AudioService.instance.ui();
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => const PuzzleScreen(mode: PuzzleMode.zen)));
  }

  Future<void> _toggleMute() async {
    await AudioService.instance.setMuted(!_muted);
    if (mounted) setState(() => _muted = AudioService.instance.muted);
    AudioService.instance.ui();   // audible only when now un-muted — a confirm
  }

  @override
  Widget build(BuildContext context) {
    final today = DailyService.todayStr();
    return Scaffold(
      backgroundColor: const Color(0xff04050a),
      body: SafeArea(
        child: Stack(
          children: [
            // ── Field Guide (top-left) ──────────────────────────────────────
            Positioned(
              top: 8, left: 12,
              child: GestureDetector(
                onTap: () {
                  AudioService.instance.ui();
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => const FieldGuideScreen()));
                },
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xff0a1018),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xff223344), width: 1),
                  ),
                  child: const Icon(Icons.menu_book_rounded,
                    color: Color(0xff7799aa), size: 20),
                ),
              ),
            ),
            // ── Mute toggle (top-right) ─────────────────────────────────────
            Positioned(
              top: 8, right: 12,
              child: GestureDetector(
                onTap: _toggleMute,
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xff0a1018),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xff223344), width: 1),
                  ),
                  child: Icon(
                    _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    color: _muted ? const Color(0xff35485a) : _cyan, size: 20),
                ),
              ),
            ),
            Column(
          children: [
            // ── Centred content ─────────────────────────────────────────────
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Title
                    const Text('SINGULARITY',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _gold, fontSize: 30, fontFamily: 'monospace',
                        fontWeight: FontWeight.bold, letterSpacing: 6,
                        shadows: [Shadow(color: Color(0x88ffc24d), blurRadius: 24)])),
                    const SizedBox(height: 4),
                    const Text('C  O  L  L  A  P  S  E',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xff99bbcc), fontSize: 12,
                        fontFamily: 'monospace', letterSpacing: 4)),

                    const SizedBox(height: 44),

                    // Black hole orb — pulsing purple glow
                    AnimatedBuilder(
                      animation: _pulse,
                      builder: (_, _) {
                        final v = sin(_pulse.value * 2 * pi) * 0.5 + 0.5;
                        return Container(
                          width: 80, height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black,
                            border: Border.all(color: _purple, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: _purple.withValues(alpha: 0.22 + v * 0.22),
                                blurRadius: 22 + v * 14, spreadRadius: 2 + v * 5),
                            ],
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 44),

                    // Streak badge — always in layout to prevent shift
                    AnimatedOpacity(
                      opacity: (_loaded && _streak > 0) ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 400),
                      child: Text('$_streak DAY STREAK',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _purple, fontSize: 11, fontFamily: 'monospace',
                          letterSpacing: 4,
                          shadows: [Shadow(color: Color(0x66bb55ff), blurRadius: 10)])),
                    ),
                    const SizedBox(height: 16),

                    // Daily button
                    _menuBtn(
                      _solvedToday ? 'ALREADY COLLAPSED' : 'TODAY\'S REGION',
                      subtitle: today,
                      color: _solvedToday ? const Color(0xff334455) : _gold,
                      onTap: _solvedToday ? null : _goDaily,
                    ),
                    const SizedBox(height: 14),

                    // Infinity button
                    _menuBtn('INFINITY MODE',
                      color: const Color(0xff44aaff),
                      onTap: _goInfinity),
                    const SizedBox(height: 14),

                    // Zen button
                    _menuBtn('ZEN MODE',
                      color: _cyan,
                      onTap: _goZen),
                  ],
                ),
              ),
            ),

            // ── Footer ──────────────────────────────────────────────────────
            const Text(
              'drag one path · consume objects in order · fill every cell',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xff3a526a), fontSize: 9,
                fontFamily: 'monospace', letterSpacing: 1)),
            const SizedBox(height: 8),
            // Dev/test launcher (discreet; remove before release).
            GestureDetector(
              onTap: () { AudioService.instance.ui(); setState(() => _showDev = true); },
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 6, horizontal: 20),
                child: Text('· dev ·',
                  style: TextStyle(
                    color: Color(0xff2c3e4e), fontSize: 9,
                    fontFamily: 'monospace', letterSpacing: 3)),
              ),
            ),
            const SizedBox(height: 12),
          ],
            ),
            if (_showDev) _buildDevOverlay(),
          ],
        ),
      ),
    );
  }

  // ── Dev/test menu: jump straight to a board with a chosen mechanic ─────────
  void _goDev(Set<PuzzleFeature> features, int level) {
    AudioService.instance.ui();
    setState(() => _showDev = false);
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => PuzzleScreen(
        mode: PuzzleMode.infinity,
        forceFeatures: features,
        fixedLevel: level)));
  }

  Widget _buildDevOverlay() => Positioned.fill(
    child: Container(
      color: const Color(0xf204050a),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('DEV · TEST FEATURE',
              style: TextStyle(
                color: _gold, fontSize: 16, fontFamily: 'monospace',
                fontWeight: FontWeight.bold, letterSpacing: 3)),
            const SizedBox(height: 4),
            const Text('forces the mechanic on every board',
              style: TextStyle(
                color: Color(0xff6688aa), fontSize: 9, fontFamily: 'monospace',
                letterSpacing: 1)),
            const SizedBox(height: 24),
            _devBtn('NORMAL',         const <PuzzleFeature>{}, 4),
            _devBtn('WORMHOLE',       {PuzzleFeature.wormhole}, 5),
            _devBtn('MASS GATE',      {PuzzleFeature.massGate}, 8),
            _devBtn('GRAVITY WELL',   {PuzzleFeature.gravityWell}, 11),
            _devBtn('ENTANGLED PAIR', {PuzzleFeature.entangled}, 8),
            // Entangled is exclusive (it reshapes the solution), so keep it out
            // of the combined set.
            _devBtn('ALL (NO QUANTUM)', {
              PuzzleFeature.wormhole, PuzzleFeature.massGate,
              PuzzleFeature.gravityWell,
            }, 12),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => setState(() => _showDev = false),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 56),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 40),
                decoration: BoxDecoration(
                  color: const Color(0xff0a1018),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xff7799aa), width: 1.2),
                ),
                child: const Text('CLOSE',
                  style: TextStyle(
                    color: Color(0xff7799aa), fontSize: 12, fontFamily: 'monospace',
                    fontWeight: FontWeight.bold, letterSpacing: 2)),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _devBtn(String label, Set<PuzzleFeature> f, int level) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: GestureDetector(
      onTap: () => _goDev(f, level),
      child: Container(
        width: 250,
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 18),
        decoration: BoxDecoration(
          color: const Color(0xff0a1018),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xff223344), width: 1.2),
        ),
        child: Text(label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xffaecbe0), fontSize: 12, fontFamily: 'monospace',
            fontWeight: FontWeight.bold, letterSpacing: 2)),
      ),
    ),
  );

  Widget _menuBtn(String label, {
    String? subtitle,
    required Color color,
    VoidCallback? onTap,
  }) {
    final active = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 36),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          color: const Color(0xff0a1018),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: color.withValues(alpha: active ? 0.65 : 0.20), width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: active ? color : color.withValues(alpha: 0.35),
                fontSize: 13, fontFamily: 'monospace',
                fontWeight: FontWeight.bold, letterSpacing: 3,
                shadows: active
                  ? [Shadow(color: color.withValues(alpha: 0.40), blurRadius: 10)]
                  : null)),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: (active ? color : color.withValues(alpha: 0.35))
                    .withValues(alpha: 0.55),
                  fontSize: 9, fontFamily: 'monospace', letterSpacing: 2)),
            ],
          ],
        ),
      ),
    );
  }
}
