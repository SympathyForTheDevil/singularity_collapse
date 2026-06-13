import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:singularity_collapse/achievement_service.dart';
import 'package:singularity_collapse/audio.dart';
import 'package:singularity_collapse/daily_service.dart';
import 'package:singularity_collapse/premium_service.dart';
import 'package:singularity_collapse/progress_service.dart';
import 'package:singularity_collapse/puzzle_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A UTC date string [delta] days from today, in DailyService's format.
  String dateAgo(int delta) {
    final d = DateTime.now().toUtc().subtract(Duration(days: delta));
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  test('streak: consecutive day increments', () async {
    SharedPreferences.setMockInitialValues(
      {'last_solved_date': dateAgo(1), 'streak': 5, 'streak_freezes': 0});
    final r = await DailyService.markSolvedAndGetStreak();
    expect(r.streak, 6);
    expect(r.freezeUsed, isFalse);
  });

  test('streak: a freeze bridges a missed day', () async {
    SharedPreferences.setMockInitialValues(
      {'last_solved_date': dateAgo(2), 'streak': 5, 'streak_freezes': 1});
    final r = await DailyService.markSolvedAndGetStreak();
    expect(r.streak, 6);            // preserved
    expect(r.freezeUsed, isTrue);
    expect(r.freezes, 0);           // consumed
  });

  test('streak: a missed day with no freeze breaks the streak', () async {
    SharedPreferences.setMockInitialValues(
      {'last_solved_date': dateAgo(2), 'streak': 5, 'streak_freezes': 0});
    final r = await DailyService.markSolvedAndGetStreak();
    expect(r.streak, 1);
    expect(r.freezeUsed, isFalse);
  });

  test('streak: a freeze is earned at 7 days (capped at 2)', () async {
    SharedPreferences.setMockInitialValues(
      {'last_solved_date': dateAgo(1), 'streak': 6, 'streak_freezes': 0});
    final r = await DailyService.markSolvedAndGetStreak();
    expect(r.streak, 7);
    expect(r.freezeEarned, isTrue);
    expect(r.freezes, 1);
  });

  test('difficulty ramps with level, not just board size', () {
    double meanDiff(int level) {
      var sum = 0;
      for (var s = 0; s < 40; s++) {
        sum += PuzzleGrid.generate(level, rng: Random(s)).difficulty;
      }
      return sum / 40;
    }
    // Levels 1 and 2 share a 5x5 board, yet 2 is meaningfully harder.
    expect(meanDiff(2), greaterThan(meanDiff(1)));
    // And difficulty keeps climbing across the range.
    expect(meanDiff(5),  greaterThan(meanDiff(2)));
    expect(meanDiff(10), greaterThan(meanDiff(5)));
  });

  test('generated puzzles are solvable (cover-all Hamiltonian) and well-formed', () {
    for (var level = 1; level <= 12; level++) {
      final g = PuzzleGrid.generate(level);
      // Solution covers every cell exactly once.
      expect(g.solution.length, g.cellCount);
      expect(g.solution.toSet().length, g.cellCount);
      // Milestone 1 is at the start, the Black Hole at the final cell.
      expect(g.startCell, g.solution.first);
      expect(g.blackHoleCell, g.solution.last);
      // Consecutive solution steps are linked (grid-adjacent OR a wormhole twin)
      // and, for real grid edges, wall-free.
      var wormJumps = 0;
      for (var i = 0; i + 1 < g.solution.length; i++) {
        final a = g.solution[i], b = g.solution[i + 1];
        if (g.adjacent(a, b)) {
          expect(g.hasWall(a, b), isFalse);
        } else {
          // The only non-adjacent consecutive step allowed is the wormhole.
          expect(g.wormholeTwin(a), b);
          wormJumps++;
        }
      }
      // At most one wormhole jump, and its twins are symmetric and non-adjacent.
      expect(wormJumps, lessThanOrEqualTo(1));
      g.wormholes.forEach((a, b) {
        expect(g.wormholes[b], a);
        expect(g.adjacent(a, b), isFalse);
      });
    }
  });

  test('hint: every solution step is reachable for all mechanics', () {
    // The guided HINT rewinds to the longest solution prefix, then steps
    // solution[t] — which must be reachable from solution[t-1]. That holds iff
    // every consecutive solution step is `linked` (grid-adjacent + wall-free, or a
    // wormhole/bridge jump). Wells & gated edges are grid-adjacent, so covered.
    final forces = <Set<PuzzleFeature>>[
      {},
      {PuzzleFeature.wormhole},
      {PuzzleFeature.massGate},
      {PuzzleFeature.gravityWell},
      {PuzzleFeature.entangled},
      {PuzzleFeature.wormhole, PuzzleFeature.massGate, PuzzleFeature.gravityWell},
      {PuzzleFeature.multiverse},
    ];
    for (final force in forces) {
      final mvBoards = force.contains(PuzzleFeature.multiverse) ? 2 : null;
      for (var seed = 0; seed < 20; seed++) {
        final g = PuzzleGrid.generate(12,
            rng: Random(seed), force: force, multiverseBoards: mvBoards);
        for (var i = 0; i + 1 < g.solution.length; i++) {
          expect(g.linked(g.solution[i], g.solution[i + 1]), isTrue,
              reason: 'force=$force seed=$seed step=$i unreachable');
        }
      }
    }
  });

  test('wormholes are skill-gated below kWormholeLevel', () {
    for (var level = 1; level < kWormholeLevel; level++) {
      // Try several seeds; early levels must never spawn a wormhole.
      for (var s = 0; s < 20; s++) {
        final g = PuzzleGrid.generate(level);
        expect(g.wormholes, isEmpty);
      }
    }
  });

  test('mass gates are skill-gated and stay solvable', () {
    // Gated below kMassGateLevel.
    for (var s = 0; s < 20; s++) {
      expect(PuzzleGrid.generate(kMassGateLevel - 1).gates, isEmpty);
    }
    // When present, the gate's boson sits earlier in the solution than the gate
    // edge → following the solution collects the key before crossing → never
    // hits a locked gate. Solvable by construction.
    for (var s = 0; s < 40; s++) {
      final g = PuzzleGrid.generate(10);
      if (g.gates.isEmpty) continue;
      final pos = {for (var i = 0; i < g.solution.length; i++) g.solution[i]: i};
      g.gates.forEach((edge, keyId) {
        var gp = -1;
        for (var i = 0; i + 1 < g.solution.length; i++) {
          if (PuzzleGrid.edgeKey(g.solution[i], g.solution[i + 1], g.cellCount) == edge) {
            gp = i; break;
          }
        }
        expect(gp, greaterThanOrEqualTo(0));
        final keyCell = g.keys.entries.firstWhere((e) => e.value == keyId).key;
        expect(pos[keyCell]!, lessThanOrEqualTo(gp));   // boson before the gate
      });
    }
  });

  test('gravity wells are skill-gated and stay solvable', () {
    // Gated below kGravityWellLevel.
    for (var s = 0; s < 20; s++) {
      expect(PuzzleGrid.generate(kGravityWellLevel - 1).wells, isEmpty);
    }
    // When present, the well sits on a straight run of `wellRange` solution
    // steps (same direction, grid-adjacent) → the launch corridor is exactly the
    // solution's next cells, so following the solution flings you correctly.
    for (var s = 0; s < 40; s++) {
      final g = PuzzleGrid.generate(12, force: {PuzzleFeature.gravityWell});
      if (g.wells.isEmpty) continue;
      final pos = {for (var i = 0; i < g.solution.length; i++) g.solution[i]: i};
      g.wells.forEach((cell, dir) {
        final i = pos[cell]!;
        expect(i + PuzzleGrid.wellRange, lessThan(g.solution.length));
        for (var srun = 0; srun < PuzzleGrid.wellRange; srun++) {
          expect(g.solution[i + srun + 1] - g.solution[i + srun], dir); // straight
          expect(g.adjacent(g.solution[i + srun], g.solution[i + srun + 1]), isTrue);
        }
      });
    }
  });

  test('entangled pair: right twin solvable, wrong twin parity-dead', () {
    int colour(int c, int size) => ((c ~/ size) + (c % size)) % 2;
    // Parity is necessary for a Hamiltonian path on a grid region from s to t.
    bool parityOk(Set<int> cells, int s, int t, int size) {
      var c0 = 0, c1 = 0;
      for (final c in cells) {
        if (colour(c, size) == 0) c0++; else c1++;
      }
      if (cells.length.isOdd) {
        final maj = c0 > c1 ? 0 : 1;
        return (c0 - c1).abs() == 1 &&
            colour(s, size) == maj && colour(t, size) == maj;
      }
      return c0 == c1 && colour(s, size) != colour(t, size);
    }
    var placed = 0;
    for (var s = 0; s < 40; s++) {
      final g = PuzzleGrid.generate(8, rng: Random(s), force: {PuzzleFeature.entangled});
      if (!g.hasQuantum) continue;
      placed++;
      final all = {for (var c = 0; c < g.cellCount; c++) c};
      final start = g.solution.first, end = g.solution.last;
      expect(g.solution.length, g.fillCount);            // covers all but the ghost
      expect(g.solution.contains(g.quantumCell), isTrue);
      expect(g.solution.contains(g.ghostCell), isFalse);
      // Right branch (minus ghost) is the solution → parity holds.
      expect(parityOk(all.difference({g.ghostCell}), start, end, g.size), isTrue);
      // Wrong branch (minus the on-path twin) breaks parity → unsolvable.
      expect(parityOk(all.difference({g.quantumCell}), start, end, g.size), isFalse);
    }
    expect(placed, greaterThan(0));
  });

  test('multiverse: N boards woven by one-way + two-way bridges, solvable', () {
    for (final boards in [2, 3]) {
    for (var seed = 0; seed < 30; seed++) {
      final g = PuzzleGrid.generate(
        12, rng: Random(seed), force: {PuzzleFeature.multiverse},
        multiverseBoards: boards);
      final na = g.size * g.cols;

      // Every board is covered exactly once by one continuous solution.
      expect(g.boardCount, boards);
      expect(g.cellCount, boards * na);
      expect(g.solution.length, g.cellCount);
      expect(g.solution.toSet().length, g.cellCount);
      expect(g.solution.map(g.boardOf).toSet(),
          {for (var b = 0; b < boards; b++) b});           // visits every board

      // Every consecutive step is linked; same-board steps are grid-adjacent and
      // wall-free; cross-board steps are exactly valid bridge initiations.
      var bridgeSteps = 0;
      for (var i = 0; i + 1 < g.solution.length; i++) {
        final a = g.solution[i], b = g.solution[i + 1];
        expect(g.linked(a, b), isTrue, reason: 'step $i unlinked (seed $seed)');
        if (g.adjacent(a, b)) {
          expect(g.hasWall(a, b), isFalse);
        } else {
          // A non-adjacent step must be a legal bridge crossing from a's mouth.
          expect(g.bridgeExitFrom(a), b, reason: 'step $i illegal bridge (seed $seed)');
          bridgeSteps++;
        }
      }
      // A there-and-back weave: at least two crossings.
      expect(bridgeSteps, greaterThanOrEqualTo(2));

      // The mix: at least one one-way and one two-way bridge.
      expect(g.bridges.any((br) => br.oneWay),  isTrue);
      expect(g.bridges.any((br) => !br.oneWay), isTrue);
      // One-way exit mouths are arrival-only (can't be entered by a normal step).
      for (final br in g.bridges) {
        if (br.oneWay) expect(g.isBridgeEntryBlocked(br.b), isTrue);
      }

      // Milestone 1 at the start, Black Hole at the final cell, ordered between.
      expect(g.startCell, g.solution.first);
      expect(g.blackHoleCell, g.solution.last);
      var seen = 0;
      for (final c in g.solution) {
        final m = g.milestones[c];
        if (m != null) { expect(m, seen + 1); seen++; }
      }
      expect(seen, g.milestoneCount);
    }
    }
  });

  test('multiverse + entangled graduate into progression at their gate levels', () {
    // Below the multiverse gate, no multiverse ever auto-spawns.
    for (var level = 1; level < kMultiverseLevel; level++) {
      for (var s = 0; s < 10; s++) {
        expect(PuzzleGrid.generate(level, rng: Random(s)).boardCount, 1,
            reason: 'level $level must not be multiverse');
      }
    }
    // Guaranteed first encounters: 2 boards at the gate, 3 boards at the 3-board gate.
    for (var s = 0; s < 10; s++) {
      expect(PuzzleGrid.generate(kMultiverseLevel,  rng: Random(s)).boardCount, 2);
      expect(PuzzleGrid.generate(kMultiverse3Level, rng: Random(s)).boardCount, 3);
    }
    // The entangled pair is forced on its first-encounter level (allow the odd
    // placement miss, which falls back to a normal board).
    var entangledSeen = 0;
    for (var s = 0; s < 20; s++) {
      if (PuzzleGrid.generate(kEntangledLevel, rng: Random(s)).hasQuantum) {
        entangledSeen++;
      }
    }
    expect(entangledSeen, greaterThan(15));
  });

  test('multiverse gate is difficulty-scaled (Easy never; Medium reveals early)', () {
    // Easy passes an unreachable gate → multiverse never auto-spawns, any level.
    for (var level = 1; level <= 30; level++) {
      for (var s = 0; s < 5; s++) {
        expect(
            PuzzleGrid.generate(level, rng: Random(s), multiverseGate: 1 << 30).boardCount,
            1, reason: 'an unreachable gate must suppress multiverse at level $level');
      }
    }
    // A lowered gate (e.g. Medium ≈ 8) guarantees the first encounter at that level.
    for (var s = 0; s < 10; s++) {
      expect(PuzzleGrid.generate(8, rng: Random(s), multiverseGate: 8).boardCount, 2);
    }
  });

  test('daily badges: earned per independent condition', () {
    const par = 50;
    int b(bool bt, bool pk, int s) =>
        ProgressService.badgesFor(backtracked: bt, peeked: pk, seconds: s, parSec: par);

    // A flawless fast solve earns all four.
    final all = b(false, false, 20);   // 20 <= 25 (half par)
    expect((all & ProgressService.perfect) != 0, isTrue);
    expect((all & ProgressService.unaided) != 0, isTrue);
    expect((all & ProgressService.swift)   != 0, isTrue);
    expect((all & ProgressService.blazing) != 0, isTrue);

    // A messy, peeked, slow solve earns none.
    expect(b(true, true, 80), 0);

    // Under par but not half-par → SWIFT, not BLAZING.
    final swift = b(true, true, 40);
    expect((swift & ProgressService.swift)   != 0, isTrue);
    expect((swift & ProgressService.blazing) != 0, isFalse);
  });

  test('forced features appear regardless of level', () {
    final g1 = PuzzleGrid.generate(2, force: {PuzzleFeature.wormhole});
    expect(g1.wormholes, isNotEmpty);
    final g2 = PuzzleGrid.generate(8, force: {PuzzleFeature.massGate});
    expect(g2.gates, isNotEmpty);
    expect(g2.keys, isNotEmpty);
    final g3 = PuzzleGrid.generate(12, force: const <PuzzleFeature>{});
    expect(g3.wormholes, isEmpty);
    expect(g3.gates, isEmpty);
    expect(g3.wells, isEmpty);
  });

  // ── Music / Penrose unlock progression ─────────────────────────────────────
  test('track→achievement unlock map is internally consistent', () {
    final trackIds = {for (final t in kMusicTracks) t.id};
    final achIds   = {for (final a in kAchievements) a.id};
    for (final e in kTrackUnlock.entries) {
      expect(trackIds.contains(e.key), isTrue, reason: '${e.key} is not a track');
      expect(achIds.contains(e.value), isTrue, reason: '${e.value} not an achievement');
    }
    // Exactly one free starter track, and it is the Bach Prelude in C.
    expect(trackIds.difference(kTrackUnlock.keys.toSet()), {'bach_prelude'});
    // Korobeiniki ← Grandmaster, per the design.
    expect(kTrackUnlock['korobeiniki'], 'grandmaster');
  });

  test('entropy-ladder unlock achievements exist with the right gates', () {
    final byId = {for (final a in kAchievements) a.id: a};
    expect(byId['red_giant']?.stat, 'easy_level');
    expect(byId['red_giant']?.target, 16);
    expect(byId['event_horizon']?.stat, 'medium_level');
    expect(byId['event_horizon']?.target, 16);
  });

  test('a fresh player has only the free track unlocked', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await AchievementService.unlockedTracks(), {'bach_prelude'});
  });

  test('500 solves unlocks Korobeiniki (Grandmaster), not the entropy-gated ones', () async {
    SharedPreferences.setMockInitialValues({'lifetime_stats': '{"solved":500}'});
    final tracks = await AchievementService.unlockedTracks();
    expect(tracks.contains('korobeiniki'), isTrue);        // Grandmaster (500)
    expect(tracks.contains('satie_gymnopedie'), isTrue);   // Apprentice (10)
    expect(tracks.contains('sugar_plum'), isFalse);        // needs Red Giant (Medium)
  });

  test('Easy Lv 16 unlocks Red Giant (Medium) → Sugar Plum', () async {
    SharedPreferences.setMockInitialValues({'entropy_maxlevel_easy': 16});
    expect((await AchievementService.unlockedIds()).contains('red_giant'), isTrue);
    expect((await AchievementService.unlockedTracks()).contains('sugar_plum'), isTrue);
  });

  test('Medium Lv 16 unlocks Event Horizon (Hard) → Toccata + Penrose gate', () async {
    SharedPreferences.setMockInitialValues({'entropy_maxlevel_medium': 16});
    // Event Horizon is also the Penrose-skin gate (home reads the same condition).
    expect((await AchievementService.unlockedIds()).contains('event_horizon'), isTrue);
    expect((await AchievementService.unlockedTracks()).contains('toccata_techno'), isTrue);
  });

  group('PremiumService daily assist allowances', () {
    test('fresh player: free caps, not premium', () async {
      SharedPreferences.setMockInitialValues({});
      await PremiumService.load();
      expect(PremiumService.premium, isFalse);
      expect(PremiumService.canHint, isTrue);
      expect(PremiumService.hintsLeft, PremiumService.freeHintsPerDay);
      expect(PremiumService.solutionsLeft, PremiumService.freeSolutionsPerDay);
    });

    test('hints deplete, then a rewarded ad tops them up', () async {
      SharedPreferences.setMockInitialValues({});
      await PremiumService.load();
      for (var i = 0; i < PremiumService.freeHintsPerDay; i++) {
        expect(PremiumService.canHint, isTrue);
        await PremiumService.useHint();
      }
      expect(PremiumService.canHint, isFalse);
      expect(PremiumService.hintsLeft, 0);
      await PremiumService.grantAdHints();
      expect(PremiumService.canHint, isTrue);
      expect(PremiumService.hintsLeft, PremiumService.adHintGrant);
    });

    test('solutions deplete, then a rewarded ad tops them up', () async {
      SharedPreferences.setMockInitialValues({});
      await PremiumService.load();
      for (var i = 0; i < PremiumService.freeSolutionsPerDay; i++) {
        await PremiumService.useSolution();
      }
      expect(PremiumService.canSolution, isFalse);
      await PremiumService.grantAdSolution();
      expect(PremiumService.canSolution, isTrue);
      expect(PremiumService.solutionsLeft, PremiumService.adSolutionGrant);
    });

    test('premium overrides all caps (unlimited)', () async {
      SharedPreferences.setMockInitialValues({});
      await PremiumService.load();
      for (var i = 0; i < 20; i++) {
        await PremiumService.useHint();
        await PremiumService.useSolution();
      }
      await PremiumService.setPremium(true);
      expect(PremiumService.canHint, isTrue);
      expect(PremiumService.canSolution, isTrue);
      expect(PremiumService.hintsLeft, -1);
      expect(PremiumService.solutionsLeft, -1);
    });

    test('counters reset on the UTC day rollover', () async {
      SharedPreferences.setMockInitialValues({
        'assist_day': '2000-01-01',        // a stale day → load() rolls it over
        'assist_hints_used': 99,
        'assist_sols_used': 99,
      });
      await PremiumService.load();
      expect(PremiumService.hintsLeft, PremiumService.freeHintsPerDay);
      expect(PremiumService.solutionsLeft, PremiumService.freeSolutionsPerDay);
    });
  });
}
