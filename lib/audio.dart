import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A selectable music track. [id] is the persisted key (empty string = none/off);
/// the piece is synthesized on demand from note data (see [AudioService]).
class MusicTrack {
  final String id;
  final String title;
  final String composer;
  const MusicTrack(this.id, this.title, this.composer);
}

/// The classical soundtrack catalogue. Grows as pieces are transcribed; each id
/// maps to a `_pieceFor` builder in [AudioService].
const List<MusicTrack> kMusicTracks = [
  MusicTrack('bach_prelude', 'Prelude in C', 'J.S. Bach'),
  MusicTrack('satie_gymnopedie', 'Gymnopédie No. 1', 'Erik Satie'),
  MusicTrack('chopin_prelude_a', 'Prelude in A', 'F. Chopin'),
];

/// All game audio. Hybrid design:
///  • procedural, perfectly-tuned synthesis for the musical/ambient layers
///    (milestone ladder notes, step ticks, the "denied" nudge, the ambient pad)
///    — asset-free, no licensing, fully tunable;
///  • a rich layered synthesised collapse stinger that occupies the designed
///    "impact one-shot" slot. To upgrade an impact moment with a produced sample
///    later, drop a file in assets/audio/ and load it in [_buildSounds] via
///    `_soloud.loadAsset(...)` — everything else stays the same.
///
/// Everything runs through one [SoLoud] engine with a global Freeverb send for a
/// lush cosmic space. Low-latency and cross-platform (Android + iOS + more).
///
/// **Music** is an optional looping soundtrack of public-domain classical pieces,
/// *synthesized* the same way as everything else (no audio assets, no recording
/// licensing) — note data → a soft music-box voice → one seamless looping buffer.
/// On-theme nod: Game Boy Tetris's "Music B" was itself a chiptune Bach minuet.
class AudioService with WidgetsBindingObserver {
  AudioService._();
  static final AudioService instance = AudioService._();

  static const _sr     = 44100;       // sample rate
  static const _muteKey = 'audio_muted';

  final SoLoud _soloud = SoLoud.instance;
  bool _ready = false;
  bool _muted = false;
  bool get muted => _muted;

  // Milestone notes (one per lower cosmic tier), ascending a pentatonic scale.
  final List<AudioSource> _notes = [];
  AudioSource? _step;
  AudioSource? _denied;
  AudioSource? _collapse;
  AudioSource? _ui;
  AudioSource? _warp;
  AudioSource? _unlock;
  AudioSource? _sling;
  AudioSource? _measure;
  AudioSource? _bridge;
  AudioSource? _pad;
  SoundHandle? _padHandle;

  // Music — a looping classical soundtrack, synthesized lazily on first use. It
  // plays only while a "music context" is active (a game mode, or the settings
  // preview) — never on the main menu — and pauses when the app is backgrounded.
  final Map<String, AudioSource> _music = {};   // id → rendered loop
  SoundHandle? _musicHandle;
  bool _musicContext  = false;     // a game / settings screen is active
  bool _backgrounded  = false;     // app is in the background (lock / app switch)
  bool _musicStarting = false;     // guard against overlapping async starts
  String _musicTrack  = '';        // current track id ('' = off)
  String _lastTrack   = '';        // last non-empty pick (for the pause toggle)
  double _musicVolume = 0.7;       // 0..1, user setting
  double _padTarget   = 0;         // current ambient-pad fade target (for ducking)
  static const _musicKey     = 'music_track';
  static const _lastTrackKey = 'music_last_track';
  static const _musicVolKey  = 'music_volume';
  String get musicTrack  => _musicTrack;
  double get musicVolume => _musicVolume;
  /// The track the pause-menu "music on" should resume — the last real pick, or
  /// the first catalogue entry if the player has never chosen one.
  String get lastTrack => _lastTrack.isNotEmpty
      ? _lastTrack
      : (kMusicTracks.isNotEmpty ? kMusicTracks.first.id : '');

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  Future<void> init() async {
    if (_ready) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _muted       = prefs.getBool(_muteKey) ?? false;
      _musicTrack  = prefs.getString(_musicKey) ?? '';
      _lastTrack   = prefs.getString(_lastTrackKey) ?? '';
      _musicVolume = prefs.getDouble(_musicVolKey) ?? 0.7;
      WidgetsBinding.instance.addObserver(this);   // pause audio in background

      await _soloud.init(sampleRate: _sr, channels: Channels.stereo);

      // Lush cosmic reverb on the global bus. Wrapped separately so a filter
      // hiccup never costs us the dry audio.
      try {
        final rv = _soloud.filters.freeverbFilter;
        rv.activate();
        rv.wet.value      = 0.32;
        rv.roomSize.value = 0.72;
        rv.damp.value     = 0.35;
        rv.width.value    = 1.0;
      } catch (e) {
        debugPrint('Audio: reverb unavailable ($e)');
      }

      await _buildSounds();
      _ready = true;
      // Music starts only when a game/settings screen calls enterMusicContext().
    } catch (e) {
      debugPrint('Audio: init failed, continuing silently ($e)');
      _ready = false;
    }
  }

  Future<void> setMuted(bool value) async {
    _muted = value;
    if (value) stopAmbient();
    _updateMusic();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_muteKey, value);
  }

  // ── Public SFX ───────────────────────────────────────────────────────────
  /// A cosmic object is consumed. [milestone] is its 1-based number; it climbs
  /// the pentatonic ladder so a full solve plays a little ascending melody.
  void milestone(int milestone) {
    if (!_ready || _muted || _notes.isEmpty) return;
    final i = (milestone - 1).clamp(0, _notes.length - 1);
    _soloud.play(_notes[i], volume: 0.55);
  }

  /// A plain cell was filled. A quiet tick, brightening with path [progress]
  /// (0..1), for tactile rhythm without fatigue.
  void step(double progress) {
    if (!_ready || _muted || _step == null) return;
    final h = _soloud.play(_step!, volume: 0.16);
    _soloud.setRelativePlaySpeed(h, 0.92 + progress.clamp(0.0, 1.0) * 0.55);
  }

  /// Tried to enter the Black Hole too early — a soft dissonant "not yet".
  void denied() {
    if (!_ready || _muted || _denied == null) return;
    _soloud.play(_denied!, volume: 0.4);
  }

  /// The region collapses — the big payoff stinger (synced to the 2s animation).
  void collapse() {
    if (!_ready || _muted || _collapse == null) return;
    _soloud.play(_collapse!, volume: 0.9);
  }

  /// Soft UI confirmation for menu / control taps.
  void ui() {
    if (!_ready || _muted || _ui == null) return;
    _soloud.play(_ui!, volume: 0.3);
  }

  /// Worldline teleported through a wormhole — a quick portal whoosh.
  void warp() {
    if (!_ready || _muted || _warp == null) return;
    _soloud.play(_warp!, volume: 0.5);
  }

  /// Collected a boson → a mass gate opens: a low thunk + rising chime.
  void unlock() {
    if (!_ready || _muted || _unlock == null) return;
    _soloud.play(_unlock!, volume: 0.6);
  }

  /// Flung by a gravity well — a quick descending "fwip".
  void slingshot() {
    if (!_ready || _muted || _sling == null) return;
    _soloud.play(_sling!, volume: 0.5);
  }

  /// Entangled superposition collapses on measurement — a glassy shimmer.
  void measure() {
    if (!_ready || _muted || _measure == null) return;
    _soloud.play(_measure!, volume: 0.55);
  }

  /// Worldline crossed a multiverse bridge to another universe — a deep rising
  /// sweep into a bright emergence shimmer (more interdimensional than a warp).
  void bridge() {
    if (!_ready || _muted || _bridge == null) return;
    _soloud.play(_bridge!, volume: 0.55);
  }

  // ── Ambient bed ────────────────────────────────────────────────────────────
  Future<void> startAmbient({bool calm = false}) async {
    if (!_ready || _muted || _pad == null || _padHandle != null) return;
    _padTarget = calm ? 0.42 : 0.28;
    final h = _soloud.play(_pad!, volume: 0, looping: true);
    _padHandle = h;
    _soloud.setProtectVoice(h, true);
    // Duck the pad under any active soundtrack so the melody reads on top.
    final target = _musicHandle != null ? _padTarget * 0.5 : _padTarget;
    _soloud.fadeVolume(h, target, const Duration(milliseconds: 1800));
  }

  void stopAmbient() {
    final h = _padHandle;
    if (h == null) return;
    _padHandle = null;
    if (!_ready) return;
    _soloud.fadeVolume(h, 0, const Duration(milliseconds: 700));
    _soloud.schedulePause(h, const Duration(milliseconds: 750));
  }

  // ── Music (classical soundtrack) ─────────────────────────────────────────────
  /// A music-enabled screen (a game mode, or the settings preview) became active
  /// — start the soundtrack. There is deliberately no music on the main menu.
  void enterMusicContext() { _musicContext = true; _updateMusic(); }

  /// Left the music-enabled screen — stop the soundtrack.
  void exitMusicContext() { _musicContext = false; _updateMusic(); }

  /// Select a track ('' = off). Remembers the last real pick so the pause-menu
  /// toggle can resume it. Persisted; previews immediately if a context is active.
  Future<void> setTrack(String id) async {
    _musicTrack = id;
    if (id.isNotEmpty) _lastTrack = id;
    _stopMusic();            // swap cleanly before (maybe) starting the new one
    _updateMusic();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_musicKey, id);
    if (id.isNotEmpty) await prefs.setString(_lastTrackKey, id);
  }

  Future<void> setMusicVolume(double v) async {
    _musicVolume = v.clamp(0.0, 1.0);
    final h = _musicHandle;
    if (_ready && h != null) _soloud.setVolume(h, _musicVolume);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_musicVolKey, _musicVolume);
  }

  /// Start or stop the loop to match the current state: a track is chosen, a
  /// music context is active, audio isn't muted, and the app is foregrounded.
  void _updateMusic() {
    if (_ready && !_muted && !_backgrounded &&
        _musicContext && _musicTrack.isNotEmpty) {
      _startMusic();
    } else {
      _stopMusic();
    }
  }

  Future<void> _startMusic() async {
    if (_musicHandle != null || _musicStarting) return;
    if (!_ready || _muted || _backgrounded ||
        !_musicContext || _musicTrack.isEmpty) {
      return;
    }
    _musicStarting = true;
    final src = await _ensureTrack(_musicTrack);
    _musicStarting = false;
    // Conditions may have changed during the async synth — re-check before play.
    if (src == null || _musicHandle != null || !_ready || _muted ||
        _backgrounded || !_musicContext || _musicTrack.isEmpty) {
      return;
    }
    final h = _soloud.play(src, volume: 0, looping: true);
    _musicHandle = h;
    _soloud.setProtectVoice(h, true);
    _soloud.fadeVolume(h, _musicVolume, const Duration(milliseconds: 1400));
    final pad = _padHandle;          // duck the pad under the melody
    if (pad != null) {
      _soloud.fadeVolume(pad, _padTarget * 0.5, const Duration(milliseconds: 900));
    }
  }

  void _stopMusic() {
    final h = _musicHandle;
    if (h == null) return;
    _musicHandle = null;
    if (!_ready) return;
    _soloud.fadeVolume(h, 0, const Duration(milliseconds: 600));
    _soloud.schedulePause(h, const Duration(milliseconds: 650));
    final pad = _padHandle;          // restore the pad to its full bed level
    if (pad != null) {
      _soloud.fadeVolume(pad, _padTarget, const Duration(milliseconds: 900));
    }
  }

  /// Synthesize (once) and cache a track's looping buffer.
  Future<AudioSource?> _ensureTrack(String id) async {
    final cached = _music[id];
    if (cached != null) return cached;
    final piece = _pieceFor(id);
    if (piece == null) return null;
    final src = await _load('music_$id', _renderPiece(piece));
    _music[id] = src;
    return src;
  }

  // ── App lifecycle: silence all audio in the background (lock / app switch) ────
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bg = state == AppLifecycleState.paused ||
               state == AppLifecycleState.hidden;
    final fg = state == AppLifecycleState.resumed;
    if (bg && !_backgrounded) {
      _backgrounded = true;
      _applyBackground();
    } else if (fg && _backgrounded) {
      _backgrounded = false;
      _applyBackground();
    }
    // inactive / detached: transient — leave audio as-is.
  }

  /// Pause (or resume) the continuous loops so nothing plays behind a locked
  /// screen or in the app switcher. Handles are kept → instant resume, no resynth.
  void _applyBackground() {
    if (!_ready) return;
    for (final h in [_padHandle, _musicHandle]) {
      if (h != null) _soloud.setPause(h, _backgrounded);
    }
  }

  // ── Sound construction ─────────────────────────────────────────────────────
  Future<void> _buildSounds() async {
    // Milestone ladder — A-based major pentatonic, warm bells.
    const base = 220.0; // A3
    const degrees = [0, 2, 4, 7, 9, 12]; // major pentatonic semitones
    for (var i = 0; i < degrees.length; i++) {
      final f = base * pow(2, degrees[i] / 12.0);
      _notes.add(await _load('note$i', _bell(f, 0.85)));
    }
    _step     = await _load('step',     _tick(880, 0.07));
    _denied   = await _load('denied',   _deniedTone());
    _ui       = await _load('ui',       _tick(523.25, 0.05, gain: 0.6));
    _warp     = await _load('warp',     _warpSweep());
    _unlock   = await _load('unlock',   _unlockChime());
    _sling    = await _load('sling',    _slingSweep());
    _measure  = await _load('measure',  _measureChime());
    _bridge   = await _load('bridge',   _bridgeWhoosh());
    _collapse = await _load('collapse', _collapseStinger());
    _pad      = await _load('pad',      _padLoop(8.0));
  }

  Future<AudioSource> _load(String name, Float64List mono) =>
      _soloud.loadMem(name, _wav(mono));

  // ── Synthesis primitives ────────────────────────────────────────────────────
  Float64List _alloc(double durSec) => Float64List((durSec * _sr).round());

  /// Warm additive bell: fundamental + a few decaying partials, plus a slightly
  /// detuned twin for chorused warmth, soft attack and exponential decay.
  Float64List _bell(double freq, double durSec) {
    final out = _alloc(durSec);
    const partials = [
      [1.0, 1.00], [2.0, 0.45], [3.0, 0.22], [4.01, 0.12], [5.4, 0.07],
    ];
    final atk = (0.006 * _sr);
    for (var i = 0; i < out.length; i++) {
      final t   = i / _sr;
      final env = (i < atk ? i / atk : 1.0) * exp(-t * 3.6);
      var s = 0.0;
      for (final p in partials) {
        s += sin(2 * pi * freq * p[0] * t) * p[1];
        s += sin(2 * pi * freq * 1.004 * p[0] * t) * p[1] * 0.5; // detuned twin
      }
      out[i] = s * env * 0.16;
    }
    return out;
  }

  /// Short soft sine blip with a fast decay — the per-cell tick.
  Float64List _tick(double freq, double durSec, {double gain = 1.0}) {
    final out = _alloc(durSec);
    final atk = (0.002 * _sr);
    for (var i = 0; i < out.length; i++) {
      final t   = i / _sr;
      final env = (i < atk ? i / atk : 1.0) * exp(-t * 38);
      out[i] = sin(2 * pi * freq * t) * env * 0.5 * gain;
    }
    return out;
  }

  /// A quick swept "whoosh" for a wormhole teleport: pitch rises then falls.
  Float64List _warpSweep() {
    const durSec = 0.34;
    final out = _alloc(durSec);
    final atk = 0.005 * _sr;
    for (var i = 0; i < out.length; i++) {
      final t   = i / _sr;
      final x   = t / durSec;                       // 0..1
      final f   = 300 + 1100 * sin(pi * x);         // 300 → 1400 → 300
      final env = (i < atk ? i / atk : 1.0) * (1 - x);
      final vib = 1 + 0.02 * sin(2 * pi * 30 * t);
      out[i] = sin(2 * pi * f * t * vib) * env * 0.5;
    }
    return out;
  }

  /// A multiverse bridge crossing: a deep airy sweep accelerating upward
  /// (falling through the mouth) that resolves into a bright chord ringing in
  /// (emerging in the other universe). Longer and lower than the wormhole warp.
  Float64List _bridgeWhoosh() {
    const durSec = 0.5;
    final out = _alloc(durSec);
    final atk = 0.006 * _sr;
    const emerge = 0.30;                       // arrival moment (seconds)
    const chord  = [659.25, 987.77, 1318.5];   // E5, B5, E6 — bright emergence
    for (var i = 0; i < out.length; i++) {
      final t = i / _sr;
      final x = t / durSec;
      var s = 0.0;
      // Departure: low airy rise with a touch of vibrato.
      final f   = 170 + 720 * x * x;           // accelerating sweep up
      final env = (i < atk ? i / atk : 1.0) *
                  (t < emerge ? 1.0 : exp(-(t - emerge) * 6));
      s += sin(2 * pi * f * t * (1 + 0.015 * sin(2 * pi * 38 * t))) * env * 0.5;
      // Emergence: a bright chord swelling in at the arrival, ringing out.
      final d = t - emerge;
      if (d >= 0) {
        var sh = 0.0;
        for (var k = 0; k < chord.length; k++) {
          sh += sin(2 * pi * chord[k] * t) / (k + 1.4);
        }
        s += sh * (1 - exp(-d * 40)) * exp(-d * 7) * 0.22;
      }
      out[i] = s * 0.5;
    }
    return out;
  }

  /// A glassy high shimmer that glides down and rings out — a wavefunction
  /// collapsing on measurement.
  Float64List _measureChime() {
    const durSec = 0.4;
    final out = _alloc(durSec);
    const freqs = [1318.5, 1567.98, 1760.0, 2093.0];
    for (var i = 0; i < out.length; i++) {
      final t = i / _sr;
      final x = t / durSec;
      var s = 0.0;
      for (var k = 0; k < freqs.length; k++) {
        s += sin(2 * pi * freqs[k] * (1 - 0.3 * x) * t) / (k + 1.5);
      }
      out[i] = s * exp(-t * 9) * 0.3;
    }
    return out;
  }

  /// A quick descending zip — a gravity-well launch.
  Float64List _slingSweep() {
    const durSec = 0.22;
    final out = _alloc(durSec);
    final atk = 0.004 * _sr;
    for (var i = 0; i < out.length; i++) {
      final t   = i / _sr;
      final x   = t / durSec;                 // 0..1
      final f   = 900 - 650 * x;              // 900 → 250 Hz
      final env = (i < atk ? i / atk : 1.0) * (1 - x);
      out[i] = sin(2 * pi * f * t) * env * 0.5;
    }
    return out;
  }

  /// A low thunk into a rising two-note chime — a mass gate unlocking.
  Float64List _unlockChime() {
    const durSec = 0.42;
    final out = _alloc(durSec);
    for (var i = 0; i < out.length; i++) {
      final t = i / _sr;
      var s = sin(2 * pi * 90 * t) * exp(-t * 22) * 0.7;   // thunk
      if (t > 0.06) s += sin(2 * pi * 392.0 * (t - 0.06)) * exp(-(t - 0.06) * 6) * 0.30;
      if (t > 0.16) s += sin(2 * pi * 587.33 * (t - 0.16)) * exp(-(t - 0.16) * 6) * 0.35;
      out[i] = s * 0.5;
    }
    return out;
  }

  /// Low beating dissonance — the "not yet" rejection.
  Float64List _deniedTone() {
    const durSec = 0.32;
    final out = _alloc(durSec);
    final atk = (0.004 * _sr);
    for (var i = 0; i < out.length; i++) {
      final t   = i / _sr;
      final env = (i < atk ? i / atk : 1.0) * exp(-t * 9);
      final s = sin(2 * pi * 110 * t)
              + sin(2 * pi * 116.5 * t)      // ~beating, sour
              + sin(2 * pi * 220 * t) * 0.3;
      out[i] = s * env * 0.18;
    }
    return out;
  }

  /// The collapse: sub-bass implosion sweep → low boom + flash burst at the
  /// ignition (~0.8s, matching the animation) → long inharmonic shimmer tail
  /// (the new star, the zoom-out).
  Float64List _collapseStinger() {
    const durSec = 2.2;
    final out  = _alloc(durSec);
    final rnd  = Random(0xC011);
    const flashAt = 0.8; // seconds — aligns with solveT≈0.4 over the 2s anim
    final shimmer = [523.25, 784.0, 1046.5, 1318.5, 1567.98];
    for (var i = 0; i < out.length; i++) {
      final t = i / _sr;
      var s = 0.0;

      // Sub-bass implosion: 120Hz → 30Hz over the first second, swelling in.
      if (t < 1.05) {
        final f   = 120 - 90 * (t / 1.05);
        final env = (t < 0.35 ? t / 0.35 : 1.0) * (1 - (t / 1.05) * 0.2);
        s += sin(2 * pi * f * t) * env * 0.9;
      }

      // Ignition: low boom + a short bright noise burst around flashAt.
      final d = t - flashAt;
      if (d >= 0) {
        final boomEnv = exp(-d * 5.5);
        s += sin(2 * pi * 46 * t) * boomEnv * 0.8;          // body
        s += (rnd.nextDouble() * 2 - 1) * exp(-d * 28) * 0.5; // transient crack
      }

      // Shimmer tail: inharmonic partials ringing out as the region zooms away.
      if (d >= 0) {
        var sh = 0.0;
        for (var k = 0; k < shimmer.length; k++) {
          sh += sin(2 * pi * shimmer[k] * t) / (k + 1.6);
        }
        s += sh * exp(-d * 1.8) * 0.18;
      }

      out[i] = s * 0.55;
    }
    return out;
  }

  /// Seamlessly-looping ambient pad. Every component frequency is an integer
  /// multiple of 1/durSec, so the buffer loops with no click. Low, slow, wide.
  Float64List _padLoop(double durSec) {
    final out = _alloc(durSec);
    int harm(double targetHz) => (targetHz * durSec).round(); // → exact loop
    // Root C2, fifth, octave, plus a distant shimmer — all loop-locked.
    final voices = <List<double>>[
      [harm(65.41).toDouble(), 0.50],
      [harm(98.00).toDouble(), 0.34],
      [harm(130.81).toDouble(), 0.30],
      [harm(196.00).toDouble(), 0.14],
      [harm(261.63).toDouble(), 0.10],
    ];
    final lfoHz = 1 / durSec; // exactly one slow swell per loop
    for (var i = 0; i < out.length; i++) {
      final t   = i / _sr;
      final lfo = 0.7 + 0.3 * sin(2 * pi * lfoHz * t);
      var s = 0.0;
      for (final v in voices) {
        final f  = v[0] / durSec;
        final f2 = (v[0] + 1) / durSec;  // loop-locked detune → slow beat, no click
        s += sin(2 * pi * f * t) * v[1];
        s += sin(2 * pi * f2 * t) * v[1] * 0.4;
      }
      out[i] = s * lfo * 0.07;
    }
    return out;
  }

  // ── Music synthesis ──────────────────────────────────────────────────────────
  /// Map a track id to its note data. New pieces plug in here + [kMusicTracks].
  _MusicPiece? _pieceFor(String id) {
    switch (id) {
      case 'bach_prelude':
        return _bachPreludeInC();
      case 'satie_gymnopedie':
        return _satieGymnopedie();
      case 'chopin_prelude_a':
        return _chopinPreludeInA();
      default:
        return null;
    }
  }

  /// Render a piece into a single seamlessly-looping buffer. Each note's tail
  /// **wraps around** the buffer end (modular indexing), so a note struck near the
  /// loop point rings on into the next iteration exactly as in a real performance
  /// — no clicks, no gap, no tempo drift.
  Float64List _renderPiece(_MusicPiece p) {
    final spb = 60.0 / p.bpm;                     // seconds per beat
    final out = _alloc(p.loopBeats * spb);
    for (final n in p.notes) {
      if (n.midi < 0) continue;                   // rest
      final freq  = 440.0 * pow(2, (n.midi - 69) / 12.0).toDouble();
      final start = (n.start * spb * _sr).round();
      _addVoice(out, start, freq, bass: n.bass, vel: n.vel,
        decay: n.bass ? p.bassDecay : p.melodyDecay,
        ring:  n.bass ? p.bassRing  : p.melodyRing);
    }
    return out;
  }

  /// Add one music-box/celesta voice (or a softer, deeper bass voice) into [out]
  /// starting at [startSample] — soft attack, exponential decay over [ring]
  /// seconds at rate [decay] (plucky = high decay/short ring; legato = low decay/
  /// long ring). The decaying tail wraps around the buffer so the loop is seamless.
  void _addVoice(Float64List out, int startSample, double freq,
      {required bool bass, required double vel,
       required double decay, required double ring}) {
    final n = out.length;
    if (n == 0) return;
    final len = (ring * _sr).round();
    final atk = 0.006 * _sr;
    final amp = (bass ? 0.16 : 0.12) * vel;
    for (var k = 0; k < len; k++) {
      final t   = k / _sr;
      final env = (k < atk ? k / atk : 1.0) * exp(-t * decay);
      final double s = bass
          ? sin(2 * pi * freq * t) + 0.3 * sin(2 * pi * freq * 2 * t)
          : sin(2 * pi * freq * t)
              + 0.5  * sin(2 * pi * freq * 2    * t)
              + 0.25 * sin(2 * pi * freq * 3    * t)
              + 0.12 * sin(2 * pi * freq * 4.02 * t);
      out[(startSample + k) % n] += s * env * amp;
    }
  }

  /// Bach — Prelude in C, BWV 846, measures 1–4 (I → ii⁷ → V⁷ → I), the iconic
  /// broken-chord figure. Each bar = two lower notes + a three-note arpeggio,
  /// the 8-note group played twice (16 sixteenths). Loops on the C→C cadence.
  _MusicPiece _bachPreludeInC() {
    // Five chord tones per bar (MIDI): [low, low2, up1, up2, up3].
    const bars = <List<int>>[
      [60, 64, 67, 72, 76],   // C major          C E G C E
      [60, 62, 69, 74, 77],   // D min7 / C        C D A D F
      [59, 62, 67, 74, 77],   // G7 / B            B D G D F
      [60, 64, 67, 72, 76],   // C major (resolve) C E G C E
    ];
    const bass    = [48, 48, 47, 48];                       // C3 C3 B2 C3
    const pattern = [0, 1, 2, 3, 4, 2, 3, 4,
                     0, 1, 2, 3, 4, 2, 3, 4];               // 16 × 1/16
    final notes = <_Note>[];
    for (var b = 0; b < bars.length; b++) {
      notes.add(_Note(bass[b], (b * 4).toDouble(), vel: 0.9, bass: true));
      for (var i = 0; i < pattern.length; i++) {
        notes.add(_Note(bars[b][pattern[i]], b * 4 + i * 0.25,
            vel: i % 8 == 0 ? 0.55 : 0.4));
      }
    }
    return _MusicPiece(66, 16, notes);                      // 4 bars of 4/4
  }

  /// Satie — Gymnopédie No. 1 (3/4, "lent et douloureux"). The signature vamp
  /// rocks Gmaj7 ↔ Dmaj7 (low pedal bass held a bar, a soft mid chord on beats
  /// 2 & 3); over it floats the verified main phrase (Mutopia LilyPond source):
  /// F#5 A5 | G5 F#5 C#5 | B4 C#5 D5 | A4. A legato voice (long ring) suits the
  /// pedalled stillness. Loops on the 4-bar phrase.
  _MusicPiece _satieGymnopedie() {
    const gBass = 43, dBass = 38;                 // G2, D2 (low pedal)
    const gChord = [59, 62, 66];                  // B3 D4 F#4  — Gmaj7 upper
    const dChord = [57, 61, 66];                  // A3 C#4 F#4 — Dmaj7 upper
    final notes = <_Note>[];
    for (var bar = 0; bar < 4; bar++) {           // vamp: G | D | G | D
      final isG  = bar.isEven;
      final base = bar * 3.0;                     // 3 beats per bar
      notes.add(_Note(isG ? gBass : dBass, base, vel: 0.85, bass: true));
      for (final c in (isG ? gChord : dChord)) {
        notes.add(_Note(c, base + 1, vel: 0.30)); // beat 2
        notes.add(_Note(c, base + 2, vel: 0.28)); // beat 3
      }
    }
    // Lead melody (beats from loop start; bar 0 begins after a beat of rest).
    const mel = <List<double>>[
      [78, 1], [81, 2],                           // F#5 A5
      [79, 3], [78, 4], [73, 5],                  // G5 F#5 C#5
      [71, 6], [73, 7], [74, 8],                  // B4 C#5 D5
      [69, 9],                                    // A4 (held to loop)
    ];
    for (final m in mel) {
      notes.add(_Note(m[0].toInt(), m[1], vel: 0.6));
    }
    return _MusicPiece(60, 12, notes,             // 4 bars of 3/4
      melodyDecay: 1.7, melodyRing: 2.6, bassDecay: 1.5, bassRing: 2.8);
  }

  /// Chopin — Prelude in A, Op. 28 No. 7 ("Andantino", 3/4), bars 1–4: the famous
  /// gentle mazurka gesture and its rising answer (an E7→A cadence). Verified
  /// against Mutopia's public-domain LilyPond source (relative-octave notation
  /// parsed). The melody (top voice) floats over the warm RH inner chords and the
  /// LH oom-pah bass; an E4 upbeat at the loop end leads back into the C#5 downbeat.
  _MusicPiece _chopinPreludeInA() {
    final notes = <_Note>[];
    void n(int midi, double beat, double vel, {bool bass = false}) =>
        notes.add(_Note(midi, beat, vel: vel, bass: bass));

    // Melody (top voice).  C#5 D5 | B4 B4 B4 | F#5 | D#5 E5 A5 A5 A5 | E4 (upbeat)
    const mv = 0.6;
    n(73, 0.0, mv); n(74, 0.75, mv);                       // C#5 (dotted-8th) D5
    n(71, 1.0, mv); n(71, 2.0, mv); n(71, 3.0, mv);        // B4 B4 B4(held)
    n(78, 5.0, mv);                                        // F#5 (pickup)
    n(75, 6.0, mv); n(76, 6.75, mv);                       // D#5 E5
    n(81, 7.0, mv); n(81, 8.0, mv); n(81, 9.0, mv);        // A5 A5 A5(held)
    n(64, 11.0, mv);                                       // E4 upbeat → loop

    // RH inner chord tones (warm filler) — softer.
    const iv = 0.32;
    for (final b in [1.0, 2.0, 3.0]) { n(68, b, iv); n(62, b, iv); }  // G#4 D4
    n(74, 5.0, iv);                                        // D5  (under F#5)
    n(72, 6.0, iv);                                        // B#4 (chromatic)
    for (final b in [6.75, 7.0, 8.0, 9.0]) { n(73, b, iv); }          // C#5

    // LH — bass note then octave/chord on beats 2–3 (E7 for 2 bars, then A).
    n(40, 0.0, 0.8, bass: true);                           // E2
    for (final b in [1.0, 2.0, 3.0]) { n(52, b, 0.34); n(64, b, 0.34); }  // E3 E4
    n(45, 6.0, 0.8, bass: true);                           // A2
    for (final b in [7.0, 8.0, 9.0]) { n(57, b, 0.34); n(64, b, 0.34); }  // A3 E4

    return _MusicPiece(64, 12, notes,             // 4 bars of 3/4
      melodyDecay: 2.2, melodyRing: 2.0, bassDecay: 1.6, bassRing: 2.4);
  }

  /// 16-bit mono PCM WAV wrapper around float samples in [-1, 1].
  Uint8List _wav(Float64List mono) {
    final n  = mono.length;
    final bd = ByteData(44 + n * 2);
    void str(int o, String s) {
      for (var i = 0; i < s.length; i++) {
        bd.setUint8(o + i, s.codeUnitAt(i));
      }
    }
    str(0, 'RIFF');
    bd.setUint32(4, 36 + n * 2, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    bd.setUint32(16, 16, Endian.little);
    bd.setUint16(20, 1, Endian.little);       // PCM
    bd.setUint16(22, 1, Endian.little);       // mono
    bd.setUint32(24, _sr, Endian.little);
    bd.setUint32(28, _sr * 2, Endian.little); // byte rate
    bd.setUint16(32, 2, Endian.little);       // block align
    bd.setUint16(34, 16, Endian.little);      // bits/sample
    str(36, 'data');
    bd.setUint32(40, n * 2, Endian.little);
    for (var i = 0; i < n; i++) {
      final v = (mono[i].clamp(-1.0, 1.0) * 32767).round();
      bd.setInt16(44 + i * 2, v, Endian.little);
    }
    return bd.buffer.asUint8List();
  }
}

/// One note in a [_MusicPiece]: a MIDI pitch (<0 = rest) struck at [start] beats,
/// with velocity [vel]; [bass] selects the softer, longer-ringing bass voice.
class _Note {
  final int midi;
  final double start;   // beats from loop start
  final double vel;     // 0..1
  final bool bass;
  const _Note(this.midi, this.start, {this.vel = 1.0, this.bass = false});
}

/// A loopable musical phrase: [bpm], total [loopBeats] (the loop length), the
/// [notes] that fill it, and the voice envelope (melody/bass decay + ring) — high
/// decay + short ring = plucky music-box (Bach); low decay + long ring = legato
/// (Satie). Rendered by `_renderPiece` into one seamless buffer.
class _MusicPiece {
  final double bpm;
  final double loopBeats;
  final List<_Note> notes;
  final double melodyDecay, melodyRing, bassDecay, bassRing;
  const _MusicPiece(this.bpm, this.loopBeats, this.notes,
      {this.melodyDecay = 4.0, this.melodyRing = 1.1,
       this.bassDecay = 2.2, this.bassRing = 1.9});
}
