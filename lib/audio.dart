import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
class AudioService {
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
  AudioSource? _pad;
  SoundHandle? _padHandle;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  Future<void> init() async {
    if (_ready) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _muted = prefs.getBool(_muteKey) ?? false;

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
    } catch (e) {
      debugPrint('Audio: init failed, continuing silently ($e)');
      _ready = false;
    }
  }

  Future<void> setMuted(bool value) async {
    _muted = value;
    if (value) stopAmbient();
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

  // ── Ambient bed ────────────────────────────────────────────────────────────
  Future<void> startAmbient({bool calm = false}) async {
    if (!_ready || _muted || _pad == null || _padHandle != null) return;
    final h = _soloud.play(_pad!, volume: 0, looping: true);
    _padHandle = h;
    _soloud.setProtectVoice(h, true);
    _soloud.fadeVolume(h, calm ? 0.42 : 0.28, const Duration(milliseconds: 1800));
  }

  void stopAmbient() {
    final h = _padHandle;
    if (h == null) return;
    _padHandle = null;
    if (!_ready) return;
    _soloud.fadeVolume(h, 0, const Duration(milliseconds: 700));
    _soloud.schedulePause(h, const Duration(milliseconds: 750));
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
