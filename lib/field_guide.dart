import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'puzzle_model.dart';

/// A single Field Guide / tutorial entry. Several entries can share a [seenKey]
/// (e.g. the gate and its boson unlock together). [unlockLevel] is shown on the
/// blacked-out slot before the entry has been encountered.
class GuideEntry {
  final String id;          // selects the icon
  final String title;
  final String body;
  final String seenKey;     // SharedPreferences flag set on first encounter
  final int    unlockLevel;
  const GuideEntry(this.id, this.title, this.body, this.seenKey, this.unlockLevel);
}

/// Persistence for "have I encountered this yet" flags.
class GuideService {
  static const keys = [
    'seen_core', 'seen_wormhole', 'seen_gate', 'seen_well', 'seen_entangled',
    'seen_multiverse', 'seen_entropy',
  ];

  static Future<Set<String>> seen() async {
    final p = await SharedPreferences.getInstance();
    return {for (final k in keys) if (p.getBool(k) ?? false) k};
  }

  static Future<void> markSeen(String key) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(key, true);
  }
}

/// Full Field Guide listing (richer than the tutorial cards).
const List<GuideEntry> kGuideEntries = [
  GuideEntry('worldline', 'Worldline',
    'Drag ONE continuous line. It can never cross itself or revisit a cell. '
    'Fill every cell of the region to complete it.',
    'seen_core', 1),
  GuideEntry('objects', 'Cosmic Objects',
    'Seven masses, smallest to largest: Particle, Asteroid, Moon, Planet, Star, '
    'Neutron Star, Black Hole. Consume them in ascending order.',
    'seen_core', 1),
  GuideEntry('blackhole', 'The Black Hole',
    'The finish. You can only enter it once every other cell is filled — it '
    'collapses the region and ends the stage.',
    'seen_core', 1),
  GuideEntry('wormhole', 'Bi-directional Wormhole',
    'Two linked portals you can cross in EITHER direction — enter one and your '
    'worldline emerges from its twin (you cannot pass through without taking the '
    'jump). Appears within a region, and as a two-way bridge between universes.',
    'seen_wormhole', kWormholeLevel),
  GuideEntry('gate', 'Mass Gate',
    'A sealed barrier across the path. It stays locked until you collect its '
    'matching Boson.',
    'seen_gate', kMassGateLevel),
  GuideEntry('boson', 'Boson',
    'A glowing green mote — the key to a mass gate. It sits off your natural '
    'route, so plan a detour to grab it before the gate.',
    'seen_gate', kMassGateLevel),
  GuideEntry('well', 'Gravity Well',
    'Step onto it and your worldline is flung a fixed direction — no choice. Set '
    'up your approach so the launch lands where you need.',
    'seen_well', kGravityWellLevel),
  GuideEntry('entangled', 'Entangled Pair',
    'A cosmic object in superposition across two cells, joined by a quantum '
    'thread. Measure one (trace into it) and its twin collapses to a void. '
    'Exactly one collapse leaves the region fillable; the other strands you — '
    'undo and try the twin.',
    'seen_entangled', 13),
  GuideEntry('multiverse', 'Multiverse',
    'Several stacked universes, each its own colour, linked by bridges. Two-way '
    'bridges (twin portals) let you cross either direction; one-way bridges (a '
    'dark mouth feeding a bright white hole) only go one way — no return. A '
    'bridge is coloured by the universe it leads to. Fill EVERY cell of EVERY '
    'universe; finish on the Black Hole.',
    'seen_multiverse', kMultiverseLevel),
  GuideEntry('bridge', 'Einstein–Rosen Bridge',
    'A ONE-WAY bridge between universes: fall into the dark mouth and you are '
    'ejected from a bright white hole far away — but you can never return through '
    'it. (A two-way wormhole, by contrast, crosses either direction.) Its colour '
    'tells you which universe it leads to. Plan the crossing carefully.',
    'seen_multiverse', kMultiverseLevel),
];

/// The four first-encounter teaching cards (Core + the three mechanics).
const List<GuideEntry> kTutorialCards = [
  GuideEntry('worldline', 'WORLDLINE',
    'Drag one continuous line. Consume cosmic objects in ascending mass order, '
    'fill every cell, and finish on the Black Hole to collapse the region.',
    'seen_core', 1),
  GuideEntry('entropy', 'ENTROPY MODE',
    'A survival run for high score. The ENTROPY bar climbs with time — and with '
    'every backtrack, hint or peek. Solve a region to VENT it (clean + fast vents '
    'most). Let the bar fill and the region suffers HEAT DEATH and the run ends. '
    'Go deep; reach Lv 16 to unlock the next difficulty.',
    'seen_entropy', 1),
  GuideEntry('wormhole', 'WORMHOLE',
    'Two linked portals. Enter one and your line emerges from its twin — you '
    'can\'t walk through a portal without taking the jump.',
    'seen_wormhole', kWormholeLevel),
  GuideEntry('gate', 'MASS GATE',
    'A sealed barrier. Collect its green Boson — off your natural route — to '
    'open it.',
    'seen_gate', kMassGateLevel),
  GuideEntry('well', 'GRAVITY WELL',
    'Step on it and you\'re flung a fixed direction, no choice. Aim your '
    'approach so the launch lands where you need.',
    'seen_well', kGravityWellLevel),
  GuideEntry('entangled', 'ENTANGLED PAIR',
    'One object in two places. Measure one (trace into it) and its twin vanishes. '
    'Only one choice keeps the region solvable — choose well, or undo and try '
    'the other.',
    'seen_entangled', 13),
  GuideEntry('multiverse', 'MULTIVERSE',
    'Stacked universes linked by bridges. Two-way portals cross either way; '
    'one-way bridges (dark mouth → white hole) never return. A bridge is '
    'coloured by where it leads. Fill every cell of every universe.',
    'seen_multiverse', kMultiverseLevel),
];

// ── Palette (mirrors the in-game motif colours) ─────────────────────────────
const _gold   = Color(0xffffc24d);
const _portal = Color(0xff37e0d0);
const _boson  = Color(0xff66ffb0);
const _well   = Color(0xffff5ca8);
const _purple = Color(0xffbb55ff);

/// Small painted motif for a guide entry.
class GuideIcon extends StatelessWidget {
  final String id;
  final double size;
  const GuideIcon(this.id, {super.key, this.size = 44});
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size, size), painter: _GuideIconPainter(id));
}

class _GuideIconPainter extends CustomPainter {
  final String id;
  _GuideIconPainter(this.id);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final u = size.width;
    switch (id) {
      case 'worldline':
        final p = Path()
          ..moveTo(u * 0.15, u * 0.7)
          ..lineTo(u * 0.4, u * 0.7)
          ..lineTo(u * 0.4, u * 0.3)
          ..lineTo(u * 0.7, u * 0.3)
          ..lineTo(u * 0.7, u * 0.75);
        canvas.drawPath(p, Paint()
          ..color = _gold ..style = PaintingStyle.stroke ..strokeWidth = 3
          ..strokeJoin = StrokeJoin.round ..strokeCap = StrokeCap.round);
        canvas.drawCircle(Offset(u * 0.7, u * 0.75), 3.5, Paint()..color = Colors.white);
      case 'objects':
        canvas.drawCircle(Offset(u * 0.28, c.dy), u * 0.10, Paint()..color = const Color(0xff88ccff));
        canvas.drawCircle(Offset(u * 0.5, c.dy), u * 0.14, Paint()..color = const Color(0xffcccccc));
        canvas.drawCircle(Offset(u * 0.74, c.dy), u * 0.17, Paint()..color = const Color(0xffffcc33));
      case 'blackhole':
        canvas.save(); canvas.translate(c.dx, c.dy); canvas.scale(1, 0.34);
        canvas.drawCircle(Offset.zero, u * 0.32, Paint()
          ..color = const Color(0xffff7722) ..style = PaintingStyle.stroke ..strokeWidth = 3);
        canvas.restore();
        canvas.drawCircle(c, u * 0.2, Paint()..color = Colors.black);
        canvas.drawCircle(c, u * 0.2, Paint()
          ..color = _purple ..style = PaintingStyle.stroke ..strokeWidth = 2.5);
      case 'entropy':
        // A rising meter (track + red fill) under an upward arrow.
        final track = RRect.fromRectAndRadius(
          Rect.fromLTWH(u * 0.16, u * 0.46, u * 0.68, u * 0.16),
          Radius.circular(u * 0.08));
        canvas.drawRRect(track, Paint()..color = const Color(0xff1c2e3c));
        final fill = RRect.fromRectAndRadius(
          Rect.fromLTWH(u * 0.16, u * 0.46, u * 0.68 * 0.7, u * 0.16),
          Radius.circular(u * 0.08));
        canvas.drawRRect(fill, Paint()..color = const Color(0xffff4466));
        final arrow = Path()
          ..moveTo(u * 0.5, u * 0.16)
          ..lineTo(u * 0.63, u * 0.38)
          ..lineTo(u * 0.37, u * 0.38)
          ..close();
        canvas.drawPath(arrow, Paint()..color = _gold);
      case 'wormhole':
        for (final dx in [-u * 0.2, u * 0.2]) {
          canvas.drawCircle(c + Offset(dx, 0), u * 0.16, Paint()
            ..color = _portal ..style = PaintingStyle.stroke ..strokeWidth = 2.5);
          canvas.drawCircle(c + Offset(dx, 0), u * 0.07, Paint()..color = _portal.withValues(alpha: 0.6));
        }
      case 'gate':
        canvas.drawLine(Offset(u * 0.45, u * 0.2), Offset(u * 0.45, u * 0.8), Paint()
          ..color = _boson ..strokeWidth = 4 ..strokeCap = StrokeCap.round);
        canvas.drawCircle(Offset(u * 0.72, c.dy), u * 0.1, Paint()..color = _boson);
      case 'boson':
        canvas.drawCircle(c, u * 0.16, Paint()..color = _boson);
        final sp = Paint()..color = Colors.white ..strokeWidth = 2 ..strokeCap = StrokeCap.round;
        canvas.drawLine(c - Offset(u * 0.24, 0), c + Offset(u * 0.24, 0), sp);
        canvas.drawLine(c - Offset(0, u * 0.24), c + Offset(0, u * 0.24), sp);
      case 'entangled':
        const q = Color(0xffc9b8ff);
        final dash = Paint()..color = q.withValues(alpha: 0.6)..strokeWidth = 1.4;
        for (var x = u * 0.3; x < u * 0.7; x += 6) {
          canvas.drawLine(Offset(x, c.dy), Offset((x + 3).clamp(0, u * 0.7), c.dy), dash);
        }
        for (final dx in [-u * 0.2, u * 0.2]) {
          canvas.drawCircle(c + Offset(dx, 0), u * 0.13, Paint()..color = q.withValues(alpha: 0.5));
          canvas.drawCircle(c + Offset(dx, 0), u * 0.13, Paint()
            ..color = q ..style = PaintingStyle.stroke ..strokeWidth = 1.6);
        }
      case 'well':
        canvas.drawCircle(c, u * 0.18, Paint()
          ..color = _well ..style = PaintingStyle.stroke ..strokeWidth = 2.5);
        final a = Path()
          ..moveTo(c.dx - u * 0.05, u * 0.2)
          ..lineTo(c.dx + u * 0.12, c.dy)
          ..lineTo(c.dx - u * 0.05, u * 0.8);
        canvas.drawPath(a, Paint()
          ..color = _well ..style = PaintingStyle.stroke ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round);
      case 'bridge':
        const lav = Color(0xffc9b8ff);
        const cy  = Color(0xff99eeff);
        // Dark mouth (left) → radiant white hole (right), with a one-way arrow.
        canvas.drawCircle(Offset(u * 0.26, c.dy), u * 0.13,
          Paint()..color = const Color(0xff09060f));
        canvas.drawCircle(Offset(u * 0.26, c.dy), u * 0.13, Paint()
          ..color = lav ..style = PaintingStyle.stroke ..strokeWidth = 2);
        canvas.drawCircle(Offset(u * 0.74, c.dy), u * 0.10,
          Paint()..color = const Color(0xffeaffff));
        for (var k = 0; k < 8; k++) {
          final a = k * pi / 4, uu = Offset(cos(a), sin(a));
          canvas.drawLine(Offset(u * 0.74, c.dy) + uu * (u * 0.13),
            Offset(u * 0.74, c.dy) + uu * (u * 0.18),
            Paint()..color = cy ..strokeWidth = 1.4 ..strokeCap = StrokeCap.round);
        }
        final ar = Paint()..color = lav.withValues(alpha: 0.75)
          ..strokeWidth = 1.6 ..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(u * 0.42, c.dy), Offset(u * 0.56, c.dy), ar);
        canvas.drawLine(Offset(u * 0.56, c.dy), Offset(u * 0.50, c.dy - u * 0.05), ar);
        canvas.drawLine(Offset(u * 0.56, c.dy), Offset(u * 0.50, c.dy + u * 0.05), ar);
      case 'multiverse':
        const azure = Color(0xff36d0ff);
        // Two stacked universe panels (gold + azure) linked by a portal bridge.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(u * 0.26, u * 0.16, u * 0.48, u * 0.30),
            const Radius.circular(4)),
          Paint()..color = _gold ..style = PaintingStyle.stroke ..strokeWidth = 2);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(u * 0.26, u * 0.54, u * 0.48, u * 0.30),
            const Radius.circular(4)),
          Paint()..color = azure ..style = PaintingStyle.stroke ..strokeWidth = 2);
        canvas.drawLine(Offset(c.dx, u * 0.46), Offset(c.dx, u * 0.54),
          Paint()..color = azure.withValues(alpha: 0.7) ..strokeWidth = 1.6);
        canvas.drawCircle(Offset(c.dx, u * 0.46), u * 0.055, Paint()
          ..color = _gold ..style = PaintingStyle.stroke ..strokeWidth = 2);
        canvas.drawCircle(Offset(c.dx, u * 0.54), u * 0.055, Paint()
          ..color = azure ..style = PaintingStyle.stroke ..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(_GuideIconPainter old) => old.id != id;
}

/// The Field Guide screen — every concept/object; locked ones blacked out.
class FieldGuideScreen extends StatefulWidget {
  const FieldGuideScreen({super.key});
  @override
  State<FieldGuideScreen> createState() => _FieldGuideScreenState();
}

class _FieldGuideScreenState extends State<FieldGuideScreen> {
  Set<String> _seen = {};

  @override
  void initState() {
    super.initState();
    GuideService.seen().then((s) { if (mounted) setState(() => _seen = s); });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff04050a),
      body: SafeArea(
        child: Column(
          children: [
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
                    child: Text('FIELD GUIDE',
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
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                itemCount: kGuideEntries.length,
                itemBuilder: (_, i) => _entryCard(kGuideEntries[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _entryCard(GuideEntry e) {
    final unlocked = _seen.contains(e.seenKey);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xff0a1018),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: unlocked ? const Color(0xff2a3c4e) : const Color(0xff141d27)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44, height: 44,
            child: unlocked
              ? GuideIcon(e.id)
              : const Icon(Icons.lock_outline, color: Color(0xff35485a), size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: unlocked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.title.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white, fontSize: 13, fontFamily: 'monospace',
                        fontWeight: FontWeight.bold, letterSpacing: 2)),
                    const SizedBox(height: 6),
                    Text(e.body,
                      style: const TextStyle(
                        color: Color(0xff8aa6bc), fontSize: 11.5,
                        fontFamily: 'monospace', height: 1.5)),
                  ],
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text('? ? ?     ·     UNLOCKS AT LEVEL ${e.unlockLevel}',
                    style: const TextStyle(
                      color: Color(0xff44607a), fontSize: 11,
                      fontFamily: 'monospace', letterSpacing: 2)),
                ),
          ),
        ],
      ),
    );
  }
}
