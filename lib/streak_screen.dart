import 'package:flutter/material.dart';
import 'daily_service.dart';
import 'progress_service.dart';

/// The streak hub: the current week's solves, streak counts, freeze tokens, and a
/// ladder of astrophysics-named milestone awards. A retention surface.
class StreakScreen extends StatefulWidget {
  const StreakScreen({super.key});
  @override
  State<StreakScreen> createState() => _StreakScreenState();
}

class _StreakScreenState extends State<StreakScreen> {
  static const _gold   = Color(0xffffc24d);
  static const _flame  = Color(0xffffa733);
  static const _frost  = Color(0xff7fd8ff);
  static const _purple = Color(0xffbb55ff);
  static const _dim    = Color(0xff223040);

  // Astrophysics-themed streak milestones (days → name), ascending in scale.
  static const List<(int, String)> _milestones = [
    (3, 'PHOTON'), (5, 'PARTICLE'), (7, 'ASTEROID'), (31, 'MOON'),
    (50, 'PLANET'), (100, 'STAR'), (150, 'NEUTRON STAR'), (200, 'SUPERNOVA'),
    (250, 'NEBULA'), (300, 'QUASAR'), (365, 'GALAXY'), (500, 'SINGULARITY'),
    (1000, 'BIG BANG'),
  ];

  Map<String, int> _solves = {};
  int _streak = 0, _max = 0, _freezes = 0;
  String? _lastSolved;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s  = await ProgressService.all();
    final st = await DailyService.getStreak();
    final mx = await DailyService.getMaxStreak();
    final fz = await DailyService.getFreezes();
    final ls = await DailyService.getLastSolved();
    if (mounted) {
      setState(() {
        _solves = s; _streak = st; _max = mx; _freezes = fz; _lastSolved = ls;
        _loaded = true;
      });
    }
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final now    = DateTime.now().toUtc();
    final today  = DateTime.utc(now.year, now.month, now.day);
    final start  = today.subtract(Duration(days: today.weekday % 7));   // Sunday
    final next   = _milestones.firstWhere((m) => m.$1 > _max,
        orElse: () => _milestones.last);

    DateTime? lastD;
    if (_lastSolved != null) {
      final p = _lastSolved!.split('-').map(int.parse).toList();
      lastD = DateTime.utc(p[0], p[1], p[2]);
    }
    final streakStart =
        (lastD != null && _streak > 0) ? lastD.subtract(Duration(days: _streak - 1)) : null;

    return Scaffold(
      backgroundColor: const Color(0xff04050a),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            // Header row
            Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xff0a1018),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xff223344)),
                  ),
                  child: const Icon(Icons.arrow_back_ios_new,
                    color: Color(0xff7799aa), size: 18),
                ),
              ),
              const Expanded(
                child: Text('STREAK',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _gold, fontSize: 18, fontFamily: 'monospace',
                    fontWeight: FontWeight.bold, letterSpacing: 4,
                    shadows: [Shadow(color: Color(0x66ffc24d), blurRadius: 14)])),
              ),
              const SizedBox(width: 40),
            ]),
            const SizedBox(height: 18),

            // Big streak headline + flame
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$_streak-DAY STREAK',
                        style: const TextStyle(
                          color: _gold, fontSize: 26, fontFamily: 'monospace',
                          fontWeight: FontWeight.bold, letterSpacing: 1)),
                      const SizedBox(height: 4),
                      Text(_max > 0 ? 'Next · ${next.$2} at ${next.$1} days'
                                    : 'Solve today to begin',
                        style: const TextStyle(
                          color: Color(0xff9fb4c8), fontSize: 12,
                          fontFamily: 'monospace')),
                    ],
                  ),
                ),
                Icon(Icons.local_fire_department,
                  color: _streak > 0 ? _flame : _dim, size: 56,
                  shadows: _streak > 0
                    ? [const Shadow(color: Color(0x88ffa733), blurRadius: 20)] : null),
              ],
            ),
            const SizedBox(height: 22),

            // Current week strip
            _weekStrip(start, today, lastD, streakStart),
            const SizedBox(height: 12),

            // Freeze tokens
            Row(children: [
              for (var i = 0; i < DailyService.maxFreezes; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(Icons.ac_unit, size: 18,
                    color: i < _freezes ? _frost : _dim)),
              const SizedBox(width: 6),
              Text(_freezes > 0
                  ? '$_freezes streak ${_freezes == 1 ? "freeze" : "freezes"} ready'
                  : 'No streak freezes — earn one every 7 days',
                style: const TextStyle(
                  color: Color(0xff8aa6bc), fontSize: 11, fontFamily: 'monospace')),
            ]),

            const Divider(color: Color(0xff16202c), height: 40),

            // Stats
            if (_loaded)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _stat('${_solves.length}', 'SOLVES', _frost),
                  _stat('$_streak', 'CURRENT', _gold),
                  _stat('$_max', 'BEST', _purple),
                ],
              ),
            const SizedBox(height: 24),

            // Milestone award ladder
            const Text('MILESTONES',
              style: TextStyle(
                color: Color(0xff5a7488), fontSize: 11,
                fontFamily: 'monospace', letterSpacing: 3)),
            const SizedBox(height: 12),
            SizedBox(
              height: 124,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final m in _milestones)
                    _milestoneCard(m.$1, m.$2, _max >= m.$1, m == next),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _weekStrip(DateTime start, DateTime today, DateTime? lastD, DateTime? streakStart) {
    const letters = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    final cells = <Widget>[];
    for (var i = 0; i < 7; i++) {
      final day = start.add(Duration(days: i));
      final ds  = _fmt(day);
      final today0 = day == today;
      Widget circle;
      if (day.isAfter(today)) {
        circle = _dayCircle(const Color(0xff0d1622), null, _dim, today0);
      } else if (_solves.containsKey(ds)) {
        circle = _dayCircle(_gold, Icons.check, _gold, today0, fill: true);
      } else if (streakStart != null &&
          !day.isBefore(streakStart) && !day.isAfter(lastD!)) {
        circle = _dayCircle(_frost, Icons.ac_unit, _frost, today0, fill: true);
      } else {
        circle = _dayCircle(const Color(0xff0d1622), null, _dim, today0);
      }
      cells.add(Column(children: [
        Text(letters[i], style: const TextStyle(
          color: Color(0xff5a7488), fontSize: 11, fontFamily: 'monospace',
          fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        circle,
      ]));
    }
    return Stack(
      alignment: Alignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 19, left: 24, right: 24),
          child: Container(height: 3, color: const Color(0xff16202c)),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: cells),
      ],
    );
  }

  Widget _dayCircle(Color color, IconData? icon, Color ring, bool today,
      {bool fill = false}) {
    return Container(
      width: 38, height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill ? color : const Color(0xff0d1622),
        border: Border.all(
          color: today ? Colors.white : ring.withValues(alpha: fill ? 0.0 : 0.6),
          width: today ? 2 : 1.4),
        boxShadow: fill
          ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 10)] : null,
      ),
      child: icon == null ? null
        : Icon(icon, color: fill ? const Color(0xff04111a) : ring, size: 18),
    );
  }

  Widget _stat(String value, String label, Color c) => Column(
    children: [
      Text(value, style: TextStyle(
        color: c, fontSize: 24, fontFamily: 'monospace', fontWeight: FontWeight.bold,
        shadows: [Shadow(color: c.withValues(alpha: 0.5), blurRadius: 12)])),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(
        color: Color(0xff5a7488), fontSize: 9, fontFamily: 'monospace', letterSpacing: 2)),
    ],
  );

  Widget _milestoneCard(int days, String name, bool achieved, bool isNext) {
    final c = achieved ? _gold : const Color(0xff35485a);
    return Container(
      width: 92,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xff0a1018),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isNext ? _purple
                : achieved ? _gold.withValues(alpha: 0.5)
                : const Color(0xff182430),
          width: isNext ? 1.6 : 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(achieved ? Icons.star : Icons.star_border, color: c, size: 30,
            shadows: achieved
              ? [Shadow(color: c.withValues(alpha: 0.6), blurRadius: 12)] : null),
          const SizedBox(height: 8),
          Text('$days', style: TextStyle(
            color: achieved ? Colors.white : const Color(0xff7088a0),
            fontSize: 18, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
          Text('DAYS', style: const TextStyle(
            color: Color(0xff5a7488), fontSize: 7, fontFamily: 'monospace',
            letterSpacing: 1)),
          const SizedBox(height: 4),
          Text(name, textAlign: TextAlign.center, style: TextStyle(
            color: achieved ? _gold : const Color(0xff5a7488),
            fontSize: 8.5, fontFamily: 'monospace', letterSpacing: 0.5,
            fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
