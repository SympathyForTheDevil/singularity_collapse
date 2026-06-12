import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'audio.dart';

/// Settings — the home for audio options (and room to grow: themes…). Master
/// sound on/off, separate SFX + music volume sliders, and the song checklist that
/// chooses which tracks join the in-game random rotation. Applies live + persists.
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
  late double _sfxVol;
  late double _musicVol;
  late Set<String> _enabled;

  @override
  void initState() {
    super.initState();
    final a = AudioService.instance;
    _muted    = a.muted;
    _sfxVol   = a.sfxVolume;
    _musicVol = a.musicVolume;
    _enabled  = {...a.enabledMusic};
    a.enterMusicContext();   // preview the rotation while on this screen
  }

  @override
  void dispose() {
    AudioService.instance.exitMusicContext();
    super.dispose();
  }

  Future<void> _toggleSound() async {
    await AudioService.instance.setMuted(!_muted);
    AudioService.instance.ui();   // audible only once un-muted — a confirm
    if (mounted) setState(() => _muted = AudioService.instance.muted);
  }

  void _setSfxVol(double v) {
    setState(() => _sfxVol = v);
    AudioService.instance.setSfxVolume(v);
  }

  void _setMusicVol(double v) {
    setState(() => _musicVol = v);
    AudioService.instance.setMusicVolume(v);
  }

  Future<void> _toggleEnabled(String id) async {
    final on = !_enabled.contains(id);
    AudioService.instance.ui();
    await AudioService.instance.setEnabled(id, on);
    if (mounted) {
      setState(() {
        if (on) { _enabled.add(id); } else { _enabled.remove(id); }
      });
    }
  }

  void _previewTrack(String id) {
    AudioService.instance.previewTrack(id);   // hear it without changing rotation
    setState(() {});                          // refresh the "now playing" highlight
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
                  const SizedBox(height: 16),
                  _volumeRow(Icons.graphic_eq_rounded, 'SFX', _sfxVol, _setSfxVol,
                    onEnd: () => AudioService.instance.ui()),   // tick at new level
                  const SizedBox(height: 12),
                  _volumeRow(Icons.music_note_rounded, 'MUSIC', _musicVol, _setMusicVol),

                  const SizedBox(height: 28),
                  _sectionLabel('MUSIC ROTATION'),
                  const SizedBox(height: 4),
                  const Text('tap a song to preview · check it to add · one per level',
                    style: TextStyle(
                      color: Color(0xff6688aa), fontSize: 9.5,
                      fontFamily: 'monospace', letterSpacing: 1)),
                  const SizedBox(height: 12),
                  for (final t in kMusicTracks) _trackTile(t),

                  const SizedBox(height: 28),
                  _sectionLabel('ABOUT'),
                  const SizedBox(height: 12),
                  _aboutPanel(),
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

  // ── About / credits ─────────────────────────────────────────────────────────
  static const _kVersion = '1.0.0';            // keep in sync with pubspec version
  static const _kSite    = 'https://singularitycollapse.com';
  static const _kSupport = 'mailto:support@singularitycollapse.com';
  static const _kPrivacy = 'https://singularitycollapse.com/privacy';

  Future<void> _open(String url) async {
    AudioService.instance.ui();
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {/* no handler / offline — fail quietly */}
  }

  Widget _aboutPanel() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('SINGULARITY: COLLAPSE',
            style: TextStyle(
              color: _gold, fontSize: 13, fontFamily: 'monospace',
              fontWeight: FontWeight.bold, letterSpacing: 2)),
          const SizedBox(height: 4),
          Text('v$_kVersion     ·     Developed by Adam Ettinger',
            style: const TextStyle(
              color: Color(0xff8aa6bc), fontSize: 10.5,
              fontFamily: 'monospace', letterSpacing: 0.5)),
          const SizedBox(height: 6),
          const Text('Music: public-domain works by Bach, Satie, Chopin & '
            'Tchaikovsky, synthesized in-engine.',
            style: TextStyle(
              color: Color(0xff6c89a4), fontSize: 9.5,
              fontFamily: 'monospace', letterSpacing: 0.5, height: 1.4)),
          const SizedBox(height: 10),
          Divider(color: _border.withValues(alpha: 0.6), height: 1),
          _linkRow(Icons.language_rounded, 'WEBSITE', () => _open(_kSite)),
          _linkRow(Icons.mail_outline_rounded, 'SUPPORT', () => _open(_kSupport)),
          _linkRow(Icons.privacy_tip_outlined, 'PRIVACY POLICY', () => _open(_kPrivacy)),
          _linkRow(Icons.code_rounded, 'OPEN-SOURCE LICENSES', () {
            AudioService.instance.ui();
            showLicensePage(
              context: context,
              applicationName: 'Singularity: Collapse',
              applicationVersion: 'v$_kVersion');
          }),
        ],
      ),
    );
  }

  Widget _linkRow(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: _cyan, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                style: const TextStyle(
                  color: Color(0xff9fbdd2), fontSize: 12, fontFamily: 'monospace',
                  fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            ),
            const Icon(Icons.chevron_right_rounded,
              color: Color(0xff5a7488), size: 18),
          ],
        ),
      ),
    );
  }

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

  Widget _volumeRow(IconData icon, String label, double value,
      ValueChanged<double> onChanged, {VoidCallback? onEnd}) {
    final dim = _muted;
    final col = dim ? const Color(0xff35485a) : _purple;
    return Opacity(
      opacity: dim ? 0.5 : 1.0,
      child: Row(
        children: [
          Icon(icon, color: const Color(0xff5a7488), size: 18),
          const SizedBox(width: 10),
          SizedBox(
            width: 52,
            child: Text(label,
              style: const TextStyle(
                color: Color(0xff5a7488), fontSize: 11, fontFamily: 'monospace',
                fontWeight: FontWeight.bold, letterSpacing: 2)),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: col,
                inactiveTrackColor: const Color(0xff1c2e3c),
                thumbColor: dim ? const Color(0xff35485a) : _gold,
                overlayColor: _purple.withValues(alpha: 0.15),
                trackHeight: 3,
              ),
              child: Slider(
                value: value,
                onChanged: onChanged,
                onChangeEnd: onEnd == null ? null : (_) => onEnd(),
              ),
            ),
          ),
          SizedBox(
            width: 34,
            child: Text('${(value * 100).round()}',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: col, fontSize: 11, fontFamily: 'monospace',
                fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _trackTile(MusicTrack t) {
    final on = _enabled.contains(t.id);
    final playing = AudioService.instance.currentTrack == t.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: playing ? _cyan.withValues(alpha: 0.8)
               : on ? _purple.withValues(alpha: 0.8)
               : const Color(0xff2a3c4e),
          width: (playing || on) ? 1.5 : 1),
      ),
      child: Row(
        children: [
          // Left: tap to preview (hear it without touching the rotation).
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _previewTrack(t.id),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                child: Row(
                  children: [
                    Icon(playing ? Icons.graphic_eq_rounded : Icons.play_arrow_rounded,
                      color: playing ? _cyan : const Color(0xff5a7488), size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.title.toUpperCase(),
                            style: TextStyle(
                              color: on ? Colors.white : const Color(0xff8aa6bc),
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
                  ],
                ),
              ),
            ),
          ),
          // Right: checkbox to add/remove from the rotation.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _toggleEnabled(t.id),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 14, 12),
              child: Icon(
                on ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                color: on ? _purple : const Color(0xff35485a), size: 24),
            ),
          ),
        ],
      ),
    );
  }
}
