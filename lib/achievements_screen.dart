import 'dart:math';
import 'package:flutter/material.dart';
import 'audio.dart';
import 'daily_service.dart';
import 'field_guide.dart';
import 'progress_service.dart';
import 'puzzle_model.dart';
import 'stats_service.dart';

/// One achievement: reach [target] of the merged value keyed by [stat].
class _Ach {
  final String name, desc, icon, stat;
  final int target;
  const _Ach(this.name, this.desc, this.icon, this.stat, this.target);
}

const List<_Ach> _kAch = [
  _Ach('Apprentice',          'Collapse 10 regions',              'worldline',  'solved',     10),
  _Ach('Adept',               'Collapse 50 regions',              'worldline',  'solved',     50),
  _Ach('Puzzle Master',       'Collapse 200 regions',             'blackhole',  'solved',     200),
  _Ach('Grandmaster',         'Collapse 500 regions',             'blackhole',  'solved',     500),
  _Ach('Laplace\'s Demon',    '50 flawless solves (no backtrack)','worldline',  'perfect',    50),
  _Ach('Explorer',            'Discover all five mechanics',      'objects',    'mechanics',  5),
  _Ach('Less Than 12 Parsecs','Clear 25 wormhole regions',        'wormhole',   'wormhole',   25),
  _Ach('Locksmith',           'Clear 25 mass-gate regions',       'gate',       'gate',       25),
  _Ach('Slingshot',           'Clear 25 gravity-well regions',    'well',       'well',       25),
  _Ach('Spooky Action',       'Measure 25 entangled regions',     'entangled',  'entangled',  25),
  _Ach('Many Worlds',         'Traverse 25 multiverse regions',   'multiverse', 'multiverse', 25),
  _Ach('Maxwell\'s Demon',    'Reach Entropy Lv 20',              'entropy',    'entropy',    20),
  _Ach('Dedicated',           'A 7-day daily streak',             'syntropy',   'streak',     7),
  _Ach('Devoted',             'A 30-day daily streak',            'syntropy',   'streak',     30),
];

/// The five mechanics in unlock order: (seenKey, label, iconId, gate level).
const List<(String, String, String, int)> _kMechanics = [
  ('seen_wormhole',  'WORMHOLE',     'wormhole',   kWormholeLevel),
  ('seen_gate',      'MASS GATE',    'gate',       kMassGateLevel),
  ('seen_well',      'GRAVITY WELL', 'well',       kGravityWellLevel),
  ('seen_entangled', 'ENTANGLED',    'entangled',  kEntangledLevel),
  ('seen_multiverse','MULTIVERSE',   'multiverse', kMultiverseLevel),
];

/// Achievements + the mechanics-discovered progression — reached from Home (🏆).
class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});
  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  static const _gold   = Color(0xffffc24d);
  static const _purple = Color(0xffbb55ff);
  static const _panel  = Color(0xff0a1018);
  static const _border = Color(0xff223344);
  static const _dim    = Color(0xff5a7488);

  bool _loaded = false;
  Set<String> _seen = const {};
  Map<String, int> _values = const {};   // merged stat values keyed for _kAch

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stats = await StatsService.all();
    final seen  = await GuideService.seen();
    final mech  = _kMechanics.where((m) => seen.contains(m.$1)).length;
    var entLevel = 0;
    for (final d in ['easy', 'medium', 'hard']) {
      entLevel = max(entLevel, await ProgressService.bestLevel(d));
    }
    final streak = await DailyService.getMaxStreak();
    if (!mounted) return;
    setState(() {
      _seen = seen;
      _values = {
        ...stats,
        'mechanics': mech,
        'entropy': entLevel,
        'streak': streak,
      };
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final unlocked = _kAch.where((a) => (_values[a.stat] ?? 0) >= a.target).length;
    return Scaffold(
      backgroundColor: const Color(0xff04050a),
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: _panel,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _border),
                      ),
                      child: const Icon(Icons.arrow_back_ios_new,
                        color: Color(0xff7799aa), size: 18),
                    ),
                  ),
                  const Expanded(
                    child: Text('ACHIEVEMENTS',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _gold, fontSize: 18, fontFamily: 'monospace',
                        fontWeight: FontWeight.bold, letterSpacing: 4,
                        shadows: [Shadow(color: Color(0x66ffc24d), blurRadius: 14)])),
                  ),
                  const SizedBox(width: 40),
                ],
              ),
            ),
            Expanded(
              child: !_loaded
                ? const Center(child: CircularProgressIndicator(
                    color: Color(0xff335066), strokeWidth: 2))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
                    children: [
                      _mechanicsSection(),
                      const SizedBox(height: 26),
                      _sectionLabel('ACHIEVEMENTS  ·  $unlocked / ${_kAch.length}'),
                      const SizedBox(height: 12),
                      for (final a in _kAch) _achRow(a),
                    ],
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String t) => Text(t,
      style: const TextStyle(
        color: _dim, fontSize: 12, fontFamily: 'monospace',
        fontWeight: FontWeight.bold, letterSpacing: 3));

  // ── Mechanics discovered (relocated from the home strip) ────────────────────
  Widget _mechanicsSection() {
    final discovered = _kMechanics.where((m) => _seen.contains(m.$1)).length;
    final remaining  = _kMechanics.where((m) => !_seen.contains(m.$1)).toList();
    final teaser = remaining.isEmpty
        ? 'ALL DISCOVERED'
        : 'NEXT · ${remaining.first.$2} · L${remaining.first.$4}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('MECHANICS  ·  $discovered / ${_kMechanics.length}'),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () {
            AudioService.instance.ui();
            Navigator.push(context, MaterialPageRoute(
              builder: (_) => const FieldGuideScreen()));
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final m in _kMechanics)
                      Opacity(
                        opacity: _seen.contains(m.$1) ? 1.0 : 0.22,
                        child: GuideIcon(m.$3, size: 32)),
                  ],
                ),
                const SizedBox(height: 10),
                Text('$teaser     ·     FIELD GUIDE ▸',
                  style: const TextStyle(
                    color: Color(0xff8aa6bc), fontSize: 10.5,
                    fontFamily: 'monospace', letterSpacing: 1)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── One achievement row ─────────────────────────────────────────────────────
  Widget _achRow(_Ach a) {
    final cur  = _values[a.stat] ?? 0;
    final done = cur >= a.target;
    final frac = (cur / a.target).clamp(0.0, 1.0);
    final accent = done ? _gold : _purple;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: done ? _gold.withValues(alpha: 0.7) : const Color(0xff2a3c4e),
          width: done ? 1.5 : 1),
      ),
      child: Row(
        children: [
          Opacity(opacity: done ? 1.0 : 0.32, child: GuideIcon(a.icon, size: 38)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(a.name.toUpperCase(),
                        style: TextStyle(
                          color: done ? _gold : const Color(0xff9fbdd2),
                          fontSize: 13, fontFamily: 'monospace',
                          fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                    ),
                    if (done)
                      const Icon(Icons.check_circle, color: _gold, size: 18)
                    else
                      Text('$cur / ${a.target}',
                        style: const TextStyle(
                          color: _dim, fontSize: 10, fontFamily: 'monospace',
                          fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 3),
                Text(a.desc,
                  style: const TextStyle(
                    color: Color(0xff6c89a4), fontSize: 10,
                    fontFamily: 'monospace', letterSpacing: 0.5)),
                const SizedBox(height: 8),
                // Progress bar.
                Container(
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xff0e1c28),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: frac,
                    child: Container(decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(3))),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
