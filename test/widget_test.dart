import 'package:flutter_test/flutter_test.dart';

import 'package:singularity_collapse/puzzle_model.dart';

void main() {
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
    // When present, each gate sits on a solution edge the path crosses only
    // AFTER it has collected `required` milestones → following the solution
    // never hits a locked gate.
    for (var s = 0; s < 40; s++) {
      final g = PuzzleGrid.generate(10);
      if (g.gates.isEmpty) continue;
      var visited = 0;
      for (var i = 0; i + 1 < g.solution.length; i++) {
        final a = g.solution[i], b = g.solution[i + 1];
        if (g.milestones.containsKey(a)) visited++;
        final req = g.gateAt(a, b);
        if (req != null) expect(visited, greaterThanOrEqualTo(req));
      }
    }
  });

  test('forced features appear regardless of level', () {
    final g1 = PuzzleGrid.generate(2, force: {PuzzleFeature.wormhole});
    expect(g1.wormholes, isNotEmpty);
    final g2 = PuzzleGrid.generate(8, force: {PuzzleFeature.massGate});
    expect(g2.gates, isNotEmpty);
    final g3 = PuzzleGrid.generate(12, force: const <PuzzleFeature>{});
    expect(g3.wormholes, isEmpty);
    expect(g3.gates, isEmpty);
  });
}
