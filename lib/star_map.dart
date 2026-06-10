import 'package:flutter/material.dart';
import 'daily_service.dart';
import 'progress_service.dart';

/// The Constellation — each solved daily lights a star (coloured by its medal)
/// in the current month's grid. A retention surface: come back, light the sky.
class StarMapScreen extends StatefulWidget {
  const StarMapScreen({super.key});
  @override
  State<StarMapScreen> createState() => _StarMapScreenState();
}

class _StarMapScreenState extends State<StarMapScreen> {
  static const _gold = Color(0xffffc24d);
  // —, Bronze, Silver, Gold.
  static const List<Color> _medal = [
    Color(0xff223040), Color(0xffcd7f32), Color(0xffc8d2dc), Color(0xffffc24d),
  ];
  static const _months = [
    'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE',
    'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER',
  ];

  Map<String, int> _medals = {};
  int _streak = 0;
  int _freezes = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final m = await ProgressService.all();
    final s = await DailyService.getStreak();
    final f = await DailyService.getFreezes();
    if (mounted) setState(() { _medals = m; _streak = s; _freezes = f; _loaded = true; });
  }

  String _fmt(int y, int mo, int d) =>
      '$y-${mo.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final now    = DateTime.now().toUtc();
    final y = now.year, mo = now.month;
    final daysIn = DateTime.utc(y, mo + 1, 0).day;
    final lead   = DateTime.utc(y, mo, 1).weekday % 7;   // Sun-first leading blanks

    // This-month + all-time stats.
    var monthStars = 0, golds = 0;
    _medals.forEach((k, v) {
      if (v >= ProgressService.gold) golds++;
      if (k.startsWith('$y-${mo.toString().padLeft(2, '0')}-')) monthStars++;
    });

    final cells = <Widget>[
      for (var i = 0; i < lead; i++) const SizedBox.shrink(),
      for (var d = 1; d <= daysIn; d++)
        _dayStar(d, _medals[_fmt(y, mo, d)] ?? 0, d == now.day),
    ];

    return Scaffold(
      backgroundColor: const Color(0xff04050a),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
              child: Row(
                children: [
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
                    child: Text('CONSTELLATION',
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
            Text('${_months[mo - 1]}  $y',
              style: const TextStyle(
                color: Color(0xff99bbcc), fontSize: 12,
                fontFamily: 'monospace', letterSpacing: 3)),
            const SizedBox(height: 10),

            // Streak-freeze tokens (❄ filled = available)
            if (_loaded)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('FREEZE  ', style: TextStyle(
                    color: Color(0xff5a7488), fontSize: 9,
                    fontFamily: 'monospace', letterSpacing: 2)),
                  for (var i = 0; i < DailyService.maxFreezes; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Icon(Icons.ac_unit, size: 14,
                        color: i < _freezes
                          ? const Color(0xff7fd8ff) : const Color(0xff223040))),
                ],
              ),
            const SizedBox(height: 16),

            // Stat strip
            if (_loaded)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _stat('$_streak', 'STREAK', const Color(0xffbb55ff)),
                    _stat('$monthStars', 'THIS MONTH', const Color(0xff6fb0d0)),
                    _stat('$golds', 'GOLD', _gold),
                  ],
                ),
              ),
            const SizedBox(height: 22),

            // Constellation grid
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
                child: GridView.count(
                  crossAxisCount: 7,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  children: cells,
                ),
              ),
            ),
            // Legend
            Padding(
              padding: const EdgeInsets.only(bottom: 14, top: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _legend(ProgressService.bronze, 'BRONZE'),
                  _legend(ProgressService.silver, 'SILVER'),
                  _legend(ProgressService.gold, 'GOLD'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String value, String label, Color c) => Column(
    children: [
      Text(value, style: TextStyle(
        color: c, fontSize: 22, fontFamily: 'monospace',
        fontWeight: FontWeight.bold,
        shadows: [Shadow(color: c.withValues(alpha: 0.5), blurRadius: 12)])),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(
        color: Color(0xff5a7488), fontSize: 8.5,
        fontFamily: 'monospace', letterSpacing: 1.5)),
    ],
  );

  Widget _dayStar(int day, int medal, bool today) {
    final solved = medal > 0;
    final c = _medal[medal];
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          height: 26,
          child: Center(
            child: solved
              ? Icon(Icons.star, color: c, size: 15.0 + medal * 2.5,
                  shadows: [Shadow(color: c.withValues(alpha: 0.7),
                    blurRadius: 6.0 + medal * 4)])
              : Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xff223040),
                    border: today
                      ? Border.all(color: const Color(0xff6fb0d0), width: 1.4)
                      : null)),
          ),
        ),
        Text('$day', style: TextStyle(
          color: today ? const Color(0xff9fc4dc)
                        : (solved ? const Color(0xff6a8499) : const Color(0xff32465a)),
          fontSize: 8, fontFamily: 'monospace')),
      ],
    );
  }

  Widget _legend(int medal, String label) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: Row(children: [
      Icon(Icons.star, color: _medal[medal], size: 12),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(
        color: Color(0xff5a7488), fontSize: 8.5,
        fontFamily: 'monospace', letterSpacing: 1)),
    ]),
  );
}
