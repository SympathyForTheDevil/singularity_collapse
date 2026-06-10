import 'package:flutter/material.dart';
import 'audio.dart';

/// Settings — the home for audio options (and room to grow: SFX, themes…).
/// Currently: master sound on/off, the classical music-track picker, and a music
/// volume slider. All changes apply live and persist via [AudioService].
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _gold   = Color(0xffffc24d);
  static const _cyan   = Color(0xff99eeff);
  static const _purple = Color(0xffbb55ff);
  static const _panel  = Color(0xff0a1018);
  static const _border = Color(0xff223344);

  late bool _muted;
  late String _track;
  late double _volume;

  @override
  void initState() {
    super.initState();
    final a = AudioService.instance;
    _muted  = a.muted;
    _track  = a.musicTrack;
    _volume = a.musicVolume;
    a.enterMusicContext();   // preview the soundtrack while on this screen
  }

  @override
  void dispose() {
    AudioService.instance.exitMusicContext();   // no music back on the menu
    super.dispose();
  }

  Future<void> _toggleSound() async {
    await AudioService.instance.setMuted(!_muted);
    AudioService.instance.ui();   // audible only once un-muted — a confirm
    if (mounted) setState(() => _muted = AudioService.instance.muted);
  }

  Future<void> _selectTrack(String id) async {
    if (id == _track) return;
    AudioService.instance.ui();
    await AudioService.instance.setTrack(id);
    if (mounted) setState(() => _track = id);
  }

  void _setVolume(double v) {
    setState(() => _volume = v);
    AudioService.instance.setMusicVolume(v);
  }

  @override
  Widget build(BuildContext context) {
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
                    child: Text('SETTINGS',
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

            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  _sectionLabel('AUDIO'),
                  const SizedBox(height: 10),
                  _soundToggle(),

                  const SizedBox(height: 28),
                  _sectionLabel('MUSIC'),
                  const SizedBox(height: 4),
                  const Text('synthesized public-domain classical · loops gently',
                    style: TextStyle(
                      color: Color(0xff6688aa), fontSize: 9.5,
                      fontFamily: 'monospace', letterSpacing: 1)),
                  const SizedBox(height: 12),
                  _trackTile(const MusicTrack('', 'None', 'silence'),
                    icon: Icons.music_off_rounded),
                  for (final t in kMusicTracks)
                    _trackTile(t, icon: Icons.music_note_rounded),

                  const SizedBox(height: 18),
                  _volumeControl(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(text,
      style: const TextStyle(
        color: Color(0xff5a7488), fontSize: 11, fontFamily: 'monospace',
        fontWeight: FontWeight.bold, letterSpacing: 3));

  Widget _soundToggle() {
    final on = !_muted;
    return GestureDetector(
      onTap: _toggleSound,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: on ? _cyan.withValues(alpha: 0.7) : _border,
            width: on ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Icon(on ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              color: on ? _cyan : const Color(0xff35485a), size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Text('SOUND',
                style: TextStyle(
                  color: on ? Colors.white : const Color(0xff8aa6bc),
                  fontSize: 13, fontFamily: 'monospace',
                  fontWeight: FontWeight.bold, letterSpacing: 2))),
            Text(on ? 'ON' : 'OFF',
              style: TextStyle(
                color: on ? _cyan : const Color(0xff556a7e),
                fontSize: 12, fontFamily: 'monospace',
                fontWeight: FontWeight.bold, letterSpacing: 2)),
          ],
        ),
      ),
    );
  }

  Widget _trackTile(MusicTrack t, {required IconData icon}) {
    final selected = _track == t.id;
    return GestureDetector(
      onTap: () => _selectTrack(t.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? _purple.withValues(alpha: 0.8) : const Color(0xff2a3c4e),
            width: selected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Icon(icon,
              color: selected ? _gold : const Color(0xff35485a), size: 24),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title.toUpperCase(),
                    style: TextStyle(
                      color: selected ? Colors.white : const Color(0xff8aa6bc),
                      fontSize: 13, fontFamily: 'monospace',
                      fontWeight: FontWeight.bold, letterSpacing: 2)),
                  const SizedBox(height: 2),
                  Text(t.composer,
                    style: const TextStyle(
                      color: Color(0xff5a7488), fontSize: 10,
                      fontFamily: 'monospace', letterSpacing: 1)),
                ],
              ),
            ),
            Icon(selected ? Icons.check_circle : Icons.circle_outlined,
              color: selected ? _purple : const Color(0xff35485a), size: 22),
          ],
        ),
      ),
    );
  }

  Widget _volumeControl() {
    final enabled = _track.isNotEmpty;
    final col = enabled ? _purple : const Color(0xff35485a);
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: Row(
        children: [
          const Icon(Icons.graphic_eq_rounded, color: Color(0xff5a7488), size: 18),
          const SizedBox(width: 10),
          const Text('VOLUME',
            style: TextStyle(
              color: Color(0xff5a7488), fontSize: 11, fontFamily: 'monospace',
              fontWeight: FontWeight.bold, letterSpacing: 2)),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: col,
                inactiveTrackColor: const Color(0xff1c2e3c),
                thumbColor: enabled ? _gold : const Color(0xff35485a),
                overlayColor: _purple.withValues(alpha: 0.15),
                trackHeight: 3,
              ),
              child: Slider(
                value: _volume,
                onChanged: enabled ? _setVolume : null,
              ),
            ),
          ),
          SizedBox(
            width: 34,
            child: Text('${(_volume * 100).round()}',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: col, fontSize: 11, fontFamily: 'monospace',
                fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
