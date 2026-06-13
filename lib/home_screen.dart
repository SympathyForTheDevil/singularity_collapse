import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'achievement_service.dart';
import 'achievements_screen.dart';
import 'audio.dart';
import 'daily_service.dart';
import 'field_guide.dart';
import 'progress_service.dart';
import 'puzzle_model.dart';
import 'puzzle_screen.dart';
import 'quantum_setup.dart';
import 'settings_screen.dart';
import 'streak_screen.dart';
import 'theme_service.dart';

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
  bool _penrose     = ThemeService.penrose;
  bool _showDev     = false;
  RunDifficulty _entropyDiff = RunDifficulty.medium;
  Map<RunDifficulty, int> _entropyBest = const {};
  Map<RunDifficulty, int> _maxLevel    = const {};
  bool _onboarded = false;   // played Entropy + seen the worldline/entropy cards
  static const int _kUnlockLevel = 16;   // reach this on a tier to unlock the next

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
    final prefs  = await SharedPreferences.getInstance();
    final dn     = prefs.getString('entropy_difficulty');
    final diff   = RunDifficulty.values.firstWhere(
      (x) => x.name == dn, orElse: () => RunDifficulty.medium);
    final best   = {
      for (final d in RunDifficulty.values)
        d: await ProgressService.bestEntropy(d.name),
    };
    final maxLvl = {
      for (final d in RunDifficulty.values)
        d: await ProgressService.bestLevel(d.name),
    };
    // Daily & Syntropy stay locked until the player has played Entropy once and
    // dismissed the worldline + entropy tutorial cards.
    final seen = await GuideService.seen();
    final onboarded =
        seen.contains('seen_core') && seen.contains('seen_entropy');
    bool unlocked(RunDifficulty d) => switch (d) {
      RunDifficulty.easy   => true,
      RunDifficulty.medium => (maxLvl[RunDifficulty.easy]   ?? 0) >= _kUnlockLevel,
      RunDifficulty.hard   => (maxLvl[RunDifficulty.medium] ?? 0) >= _kUnlockLevel,
    };
    // Unlocks may have changed since the last visit: refresh the music rotation and
    // revoke the Penrose skin if Hard isn't earned (it's gated behind unlocking Hard).
    AudioService.instance.setUnlockedMusic(await AchievementService.unlockedTracks());
    if (!unlocked(RunDifficulty.hard) && ThemeService.penrose) {
      await ThemeService.setPenrose(false);
    }
    if (mounted) {
      setState(() {
        _solvedToday = solved; _streak = streak;
        // Fall back to Easy if the remembered difficulty is still locked.
        _entropyDiff = unlocked(diff) ? diff : RunDifficulty.easy;
        _entropyBest = best; _maxLevel = maxLvl; _onboarded = onboarded;
        _penrose = ThemeService.penrose;
        _loaded = true;
      });
    }
  }

  bool _diffUnlocked(RunDifficulty d) => switch (d) {
    RunDifficulty.easy   => true,
    RunDifficulty.medium => (_maxLevel[RunDifficulty.easy]   ?? 0) >= _kUnlockLevel,
    RunDifficulty.hard   => (_maxLevel[RunDifficulty.medium] ?? 0) >= _kUnlockLevel,
  };

  Future<void> _goDaily() async {
    AudioService.instance.ui();
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => const PuzzleScreen(mode: PuzzleMode.daily)));
    _load();
  }

  Future<void> _goEntropy(RunDifficulty d) async {
    AudioService.instance.ui();
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => PuzzleScreen(mode: PuzzleMode.entropy, difficulty: d)));
    _load();   // refresh the best score after a run
  }

  Future<void> _saveDiff() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('entropy_difficulty', _entropyDiff.name);
  }

  void _goQuantum() {
    AudioService.instance.ui();
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => const QuantumSetupScreen()));
  }

  Future<void> _toggleMute() async {
    await AudioService.instance.setMuted(!_muted);
    if (mounted) setState(() => _muted = AudioService.instance.muted);
    AudioService.instance.ui();   // audible only when now un-muted — a confirm
  }

  /// Penrose is gated behind unlocking Hard Entropy (reach Medium Lv $_kUnlockLevel) —
  /// i.e. the Event Horizon achievement.
  bool get _penroseUnlocked => _diffUnlocked(RunDifficulty.hard);

  Future<void> _togglePenrose() async {
    if (!_penroseUnlocked) {
      AudioService.instance.denied();
      _showLockedSnack(
        'Penrose skin · unlock Hard Entropy (reach Medium Lv $_kUnlockLevel).');
      return;
    }
    AudioService.instance.ui();
    await ThemeService.setPenrose(!_penrose);
    if (mounted) setState(() => _penrose = ThemeService.penrose);
  }

  void _showLockedSnack(String msg) {
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m.showSnackBar(SnackBar(
      content: Text(msg,
        style: const TextStyle(
          color: Color(0xffcfe3f2), fontSize: 11, fontFamily: 'monospace')),
      backgroundColor: const Color(0xff0a1018),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(milliseconds: 2200),
    ));
  }

  Future<void> _goSettings() async {
    AudioService.instance.ui();
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => const SettingsScreen()));
    // The settings screen can flip the master mute — re-sync the home toggle.
    if (mounted) setState(() => _muted = AudioService.instance.muted);
  }

  @override
  Widget build(BuildContext context) {
    final today = DailyService.todayStr();

    // A tongue-in-cheek arXiv preprint id for the title masthead — date-stable so
    // it reads as "real" (YYMM + a plausible 5-digit number; the 6608 nods to the
    // daily epoch, June 8). Pure flavour.
    final now    = DateTime.now();
    final doy    = now.difference(DateTime(now.year, 1, 1)).inDays + 1;
    final arxivN = ((doy * 271 + 6608) % 100000).toString().padLeft(5, '0');
    final arxiv  = 'arXiv:${now.year % 100}'
        '${now.month.toString().padLeft(2, '0')}.$arxivN  [gr-qc]';
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
            // ── Constellation / star-map (top-left, beside the Field Guide) ──
            Positioned(
              top: 8, left: 60,
              child: GestureDetector(
                onTap: () {
                  AudioService.instance.ui();
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => const StreakScreen()));
                },
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xff0a1018),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xff223344), width: 1),
                  ),
                  child: const Icon(Icons.local_fire_department,
                    color: Color(0xff7799aa), size: 20),
                ),
              ),
            ),
            // ── Achievements + progression (top-left, third) ────────────────
            Positioned(
              top: 8, left: 108,
              child: GestureDetector(
                onTap: () {
                  AudioService.instance.ui();
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => const AchievementsScreen()));
                },
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xff0a1018),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xff223344), width: 1),
                  ),
                  child: const Icon(Icons.emoji_events_rounded,
                    color: Color(0xff7799aa), size: 20),
                ),
              ),
            ),
            // ── Penrose / spacetime board-skin toggle (top-right) ───────────
            Positioned(
              top: 8, right: 60,
              child: GestureDetector(
                onTap: _togglePenrose,
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xff0a1018),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _penrose ? _purple : const Color(0xff223344),
                      width: 1),
                  ),
                  // A tilted square = the 45° diamond board it produces; a lock
                  // until Hard Entropy (the Event Horizon achievement) is earned.
                  child: _penroseUnlocked
                    ? Transform.rotate(
                        angle: pi / 4,
                        child: Icon(Icons.crop_square_rounded,
                          color: _penrose ? _purple : const Color(0xff35485a),
                          size: 18),
                      )
                    : const Icon(Icons.lock_rounded,
                        color: Color(0xff35485a), size: 16),
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
            // ── Settings (top-right, left of Penrose) ───────────────────────
            Positioned(
              top: 8, right: 108,
              child: GestureDetector(
                onTap: _goSettings,
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xff0a1018),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xff223344), width: 1),
                  ),
                  child: const Icon(Icons.tune_rounded,
                    color: Color(0xff7799aa), size: 20),
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

                    const SizedBox(height: 12),
                    // Paper-style tagline + a fake arXiv citation (masthead flavour).
                    Text('A Hamiltonian Path to the Singularity',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _gold.withValues(alpha: 0.82), fontSize: 12.5,
                        fontFamily: 'monospace', fontStyle: FontStyle.italic,
                        letterSpacing: 0.5)),
                    const SizedBox(height: 6),
                    Text(arxiv,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xff6c89a4), fontSize: 10,
                        fontFamily: 'monospace', letterSpacing: 1)),

                    const SizedBox(height: 40),

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

                    // Daily button (locked until the player has played Entropy)
                    _menuBtn(
                      _solvedToday ? 'ALREADY COLLAPSED' : 'TODAY\'S WORLDLINE',
                      subtitle: _onboarded ? today : 'PLAY ENTROPY FIRST',
                      color: (_onboarded && !_solvedToday)
                        ? _gold : const Color(0xff334455),
                      onTap: (_onboarded && !_solvedToday) ? _goDaily : null,
                    ),
                    const SizedBox(height: 14),

                    // Entropy mode — high-score survival, pick a difficulty
                    _menuBtn('ENTROPY',
                      subtitle: 'SURVIVE · HIGH SCORE',
                      color: const Color(0xff44aaff),
                      onTap: () => _goEntropy(_entropyDiff)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [for (final d in RunDifficulty.values) _diffChip(d)],
                    ),
                    const SizedBox(height: 7),
                    Builder(builder: (_) {
                      final best = _entropyBest[_entropyDiff] ?? 0;
                      final lvl  = _maxLevel[_entropyDiff] ?? 0;
                      final line = best > 0
                        ? 'BEST  ·  $best${lvl > 0 ? '   ·   LV $lvl' : ''}'
                        : (lvl > 0 ? 'REACHED  LV $lvl' : 'NO RUNS YET');
                      final hasRuns = best > 0 || lvl > 0;
                      // Next-tier unlock hint.
                      final lock = !_diffUnlocked(RunDifficulty.medium)
                        ? 'MEDIUM unlocks at EASY · LV $_kUnlockLevel'
                        : !_diffUnlocked(RunDifficulty.hard)
                          ? 'HARD unlocks at MEDIUM · LV $_kUnlockLevel'
                          : null;
                      return Column(children: [
                        Text(line,
                          style: TextStyle(
                            color: hasRuns
                              ? const Color(0xff9fbdd2) : const Color(0xff6c89a4),
                            fontSize: 11, fontFamily: 'monospace', letterSpacing: 2,
                            fontWeight: hasRuns ? FontWeight.bold : FontWeight.normal)),
                        if (lock != null) ...[
                          const SizedBox(height: 4),
                          Text(lock,
                            style: const TextStyle(
                              color: Color(0xff6c89a4), fontSize: 10,
                              fontFamily: 'monospace', letterSpacing: 1)),
                        ],
                      ]);
                    }),
                    const SizedBox(height: 14),

                    // Syntropy button (locked until the player has played Entropy)
                    _menuBtn('SYNTROPY',
                      subtitle: _onboarded ? 'TAILOR YOUR SESSION' : 'PLAY ENTROPY FIRST',
                      color: _purple,
                      onTap: _onboarded ? _goQuantum : null),
                  ],
                ),
              ),
            ),

            // ── Footer ──────────────────────────────────────────────────────
            const Text(
              'drag one path · consume objects in order · fill every cell',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xff6c89a4), fontSize: 10.5,
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
  void _goDev(Set<PuzzleFeature> features, int level, {int? boards}) {
    AudioService.instance.ui();
    setState(() => _showDev = false);
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => PuzzleScreen(
        mode: PuzzleMode.entropy,
        forceFeatures: features,
        fixedLevel: level,
        multiverseBoards: boards)));
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
            _devBtn('MULTIVERSE ×2',  {PuzzleFeature.multiverse}, 12, boards: 2),
            _devBtn('MULTIVERSE ×3',  {PuzzleFeature.multiverse}, 12, boards: 3),
            // Entangled and multiverse are exclusive (they reshape the board), so
            // keep them out of the combined set.
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

  Widget _devBtn(String label, Set<PuzzleFeature> f, int level, {int? boards}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: GestureDetector(
      onTap: () => _goDev(f, level, boards: boards),
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

  Widget _diffChip(RunDifficulty d) {
    const labels = {
      RunDifficulty.easy: 'EASY', RunDifficulty.medium: 'MEDIUM', RunDifficulty.hard: 'HARD',
    };
    const c = Color(0xff44aaff);
    final unlocked = _diffUnlocked(d);
    final sel = _entropyDiff == d && unlocked;
    return GestureDetector(
      onTap: unlocked
          ? () {
              AudioService.instance.ui();
              setState(() => _entropyDiff = d);
              _saveDiff();
            }
          : null,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: sel ? c.withValues(alpha: 0.15) : const Color(0xff0a1018),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: sel ? c : const Color(0xff223344), width: 1.2)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!unlocked) ...[
              const Icon(Icons.lock_rounded, size: 9, color: Color(0xff44607a)),
              const SizedBox(width: 4),
            ],
            Text(labels[d]!,
              style: TextStyle(
                color: !unlocked ? const Color(0xff3a526a)
                     : sel ? c : const Color(0xff5a7488),
                fontSize: 10, fontFamily: 'monospace',
                fontWeight: FontWeight.bold, letterSpacing: 2)),
          ],
        ),
      ),
    );
  }

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
