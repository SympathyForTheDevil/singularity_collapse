import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:singularity_collapse/puzzle_model.dart';

void main() {
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

  test('multiverse: two boards woven by one-way + two-way bridges, solvable', () {
    for (var seed = 0; seed < 40; seed++) {
      final g = PuzzleGrid.generate(
        12, rng: Random(seed), force: {PuzzleFeature.multiverse});
      final na = g.size * g.size;

      // Two boards; the solution covers every cell of both exactly once.
      expect(g.boardCount, 2);
      expect(g.cellCount, 2 * na);
      expect(g.solution.length, g.cellCount);
      expect(g.solution.toSet().length, g.cellCount);
      expect(g.solution.map(g.boardOf).toSet(), {0, 1});   // genuinely visits both

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
  });

  test('multiverse is gated to force-only (never auto-spawns)', () {
    for (var level = 1; level <= 20; level++) {
      for (var s = 0; s < 10; s++) {
        expect(PuzzleGrid.generate(level, rng: Random(s)).boardCount, 1);
      }
    }
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
}
