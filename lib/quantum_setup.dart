import 'package:flutter/material.dart';
import 'audio.dart';
import 'field_guide.dart';
import 'puzzle_model.dart';
import 'puzzle_screen.dart';
import 'quantum_service.dart';

/// One selectable game type in the Quantum picker.
class _QType {
  final String label;
  final PuzzleFeature? feature;   // null = plain "Normal" board
  final String seenKey;           // unlock flag (GuideService)
  final String iconId;            // GuideIcon motif
  final int unlockLevel;
  const _QType(this.label, this.feature, this.seenKey, this.iconId, this.unlockLevel);
}

const List<_QType> _kTypes = [
  _QType('Normal',         null,                       'seen_core',      'worldline',  1),
  _QType('Wormhole',       PuzzleFeature.wormhole,     'seen_wormhole',  'wormhole',   kWormholeLevel),
  _QType('Mass Gate',      PuzzleFeature.massGate,     'seen_gate',      'gate',       kMassGateLevel),
  _QType('Gravity Well',   PuzzleFeature.gravityWell,  'seen_well',      'well',       kGravityWellLevel),
  _QType('Entangled Pair', PuzzleFeature.entangled,    'seen_entangled', 'entangled',  kEntangledLevel),
  _QType('Multiverse',     PuzzleFeature.multiverse,   'seen_multiverse','multiverse', kMultiverseLevel),
];

/// Tailor-your-session setup: pick which (unlocked) game types appear and whether
/// the run is timed, then begin. Selection is remembered via [QuantumService].
class QuantumSetupScreen extends StatefulWidget {
  const QuantumSetupScreen({super.key});
  @override
  State<QuantumSetupScreen> createState() => _QuantumSetupScreenState();
}

class _QuantumSetupScreenState extends State<QuantumSetupScreen> {
  static const _gold   = Color(0xffffc24d);
  static const _cyan   = Color(0xff99eeff);
  static const _purple = Color(0xffbb55ff);

  Set<String> _seen = {};
  late Set<PuzzleFeature> _features;
  late bool _normal;
  late bool _timed;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _features = {...QuantumService.features};
    _normal   = QuantumService.normal;
    _timed    = QuantumService.timed;
    GuideService.seen().then((s) {
      if (!mounted) return;
      setState(() {
        _seen = s;
        // First time (nothing chosen yet) → pre-select every unlocked type for a
        // rich default session; the player can pare it down.
        if (_features.isEmpty) {
          for (final t in _kTypes) {
            if (t.feature != null && s.contains(t.seenKey)) _features.add(t.feature!);
          }
        }
        _loaded = true;
      });
    });
  }

  bool _unlocked(_QType t) => t.seenKey == 'seen_core' || _seen.contains(t.seenKey);

  bool _selected(_QType t) =>
      t.feature == null ? _normal : _features.contains(t.feature);

  void _toggle(_QType t) {
    if (!_unlocked(t)) return;
    AudioService.instance.ui();
    setState(() {
      if (t.feature == null) {
        _normal = !_normal;
      } else if (_features.contains(t.feature)) {
        _features.remove(t.feature);
      } else {
        _features.add(t.feature!);
      }
    });
  }

  bool get _anySelected => _normal || _features.isNotEmpty;

  Future<void> _begin() async {
    if (!_anySelected) return;
    AudioService.instance.ui();
    QuantumService.features = {..._features};
    QuantumService.normal   = _normal;
    QuantumService.timed    = _timed;
    await QuantumService.save();
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(
      builder: (_) => PuzzleScreen(
        mode: PuzzleMode.quantum,
        quantumFeatures: {..._features},
        quantumNormal: _normal,
        quantumTimed: _timed,
      )));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff04050a),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
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
                    child: Text('SYNTROPY',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _purple, fontSize: 18, fontFamily: 'monospace',
                        fontWeight: FontWeight.bold, letterSpacing: 4,
                        shadows: [Shadow(color: Color(0x66bb55ff), blurRadius: 14)])),
                  ),
                  const SizedBox(width: 40),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('tailor your session · only unlocked types',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xff6688aa), fontSize: 10,
                  fontFamily: 'monospace', letterSpacing: 1)),
            ),

            // Timed / Relaxed toggle
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Row(
                children: [
                  Expanded(child: _modeChip('RELAXED', !_timed, _cyan,
                    () { AudioService.instance.ui(); setState(() => _timed = false); })),
                  const SizedBox(width: 10),
                  Expanded(child: _modeChip('TIMED', _timed, _gold,
                    () { AudioService.instance.ui(); setState(() => _timed = true); })),
                ],
              ),
            ),

            Expanded(
              child: _loaded
                ? ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
                    itemCount: _kTypes.length,
                    itemBuilder: (_, i) => _typeRow(_kTypes[i]),
                  )
                : const Center(child: CircularProgressIndicator(
                    color: Color(0xff335066), strokeWidth: 2)),
            ),

            // Begin
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: GestureDetector(
                onTap: _anySelected ? _begin : null,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xff0a1018),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _anySelected ? _purple : const Color(0xff223344),
                      width: 1.5),
                  ),
                  child: Text('BEGIN',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _anySelected ? _purple : const Color(0xff3a526a),
                      fontSize: 14, fontFamily: 'monospace',
                      fontWeight: FontWeight.bold, letterSpacing: 4,
                      shadows: _anySelected
                        ? [const Shadow(color: Color(0x66bb55ff), blurRadius: 12)]
                        : null)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeChip(String label, bool active, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.12) : const Color(0xff0a1018),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: active ? color : const Color(0xff223344),
            width: active ? 1.5 : 1),
        ),
        child: Text(label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: active ? color : const Color(0xff556a7e),
            fontSize: 12, fontFamily: 'monospace',
            fontWeight: FontWeight.bold, letterSpacing: 3)),
      ),
    );
  }

  Widget _typeRow(_QType t) {
    final unlocked = _unlocked(t);
    final selected = unlocked && _selected(t);
    return GestureDetector(
      onTap: () => _toggle(t),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xff0a1018),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? _purple.withValues(alpha: 0.8)
                 : unlocked ? const Color(0xff2a3c4e)
                 : const Color(0xff141d27),
            width: selected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 40, height: 40,
              child: unlocked
                ? Opacity(opacity: selected ? 1 : 0.5, child: GuideIcon(t.iconId, size: 40))
                : const Icon(Icons.lock_outline, color: Color(0xff35485a), size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: unlocked
                ? Text(t.label.toUpperCase(),
                    style: TextStyle(
                      color: selected ? Colors.white : const Color(0xff8aa6bc),
                      fontSize: 13, fontFamily: 'monospace',
                      fontWeight: FontWeight.bold, letterSpacing: 2))
                : Text('? ? ?     ·     UNLOCK AT LEVEL ${t.unlockLevel}',
                    style: const TextStyle(
                      color: Color(0xff44607a), fontSize: 11,
                      fontFamily: 'monospace', letterSpacing: 2)),
            ),
            if (unlocked)
              Icon(selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected ? _purple : const Color(0xff35485a), size: 22),
          ],
        ),
      ),
    );
  }
}
