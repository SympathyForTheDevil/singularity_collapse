import 'dart:math';

/// A single "Singularity: Collapse" puzzle.
///
/// Trace ONE continuous worldline that consumes cosmic objects in ascending
/// mass order — Particle → Asteroid → Moon → Planet → Star → Neutron Star →
/// Black Hole — while filling every cell of the region. The Black Hole is the
/// FINAL cell: reaching it (only possible once everything else is consumed)
/// collapses the region and ends the stage.
///
/// Generation guarantees solvability by building the SOLUTION first: a random
/// Hamiltonian path covering the grid. Milestone 1 is pinned to the path's
/// start and the Black Hole to its end; walls are only added to edges the
/// solution doesn't use. → infinite, always-solvable puzzles.
/// Special mechanics that can be woven into the core puzzle. Each unlocks at a
/// skill-gate level (below), or can be forced on for testing via the dev menu.
enum PuzzleFeature { wormhole, massGate, gravityWell }

/// Levels below these never spawn the feature — they unlock as skill gates so
/// players meet them only after the basic trace is second nature.
const int kWormholeLevel    = 4;
const int kMassGateLevel    = 7;
const int kGravityWellLevel = 10;

class PuzzleGrid {
  final int size;                 // square board: size × size
  final List<int> solution;       // a Hamiltonian path (cell indices, in order)
  final Map<int, int> milestones; // cellIndex -> milestone number (1..k)
  final Set<int> walls;           // blocked edges, encoded via [edgeKey]
  final Map<int, int> wormholes;  // symmetric cell<->twin links (teleport edges)
  final Map<int, int> gates;      // edgeKey -> key id that opens it
  final Map<int, int> keys;       // cell -> key id (the "boson" collectible)
  final Map<int, int> wells;      // cell -> direction delta (gravity-well launch)

  /// How many cells a gravity well flings you (in addition to the well cell).
  static const int wellRange = 2;

  PuzzleGrid({
    required this.size,
    required this.solution,
    required this.milestones,
    required this.walls,
    this.wormholes = const {},
    this.gates = const {},
    this.keys = const {},
    this.wells = const {},
  });

  /// Launch direction delta for the well on [cell], or null.
  int? wellDir(int cell) => wells[cell];

  bool isWormhole(int cell)   => wormholes.containsKey(cell);
  int? wormholeTwin(int cell) => wormholes[cell];

  /// Key id required to cross the edge a–b, or null if no gate there.
  int? gateKeyAt(int a, int b) => gates[edgeKey(a, b, cellCount)];
  /// Key id of the boson on [cell], or null.
  int? keyIdAt(int cell)        => keys[cell];

  /// Two cells are linked if they're grid-adjacent or a wormhole pair.
  bool linked(int a, int b) => adjacent(a, b) || wormholes[a] == b;

  int get cellCount      => size * size;
  int get milestoneCount => milestones.length;

  int rowOf(int i) => i ~/ size;
  int colOf(int i) => i % size;

  /// Cell holding milestone #1 (Particle) — where the worldline must begin.
  int get startCell => milestones.entries.firstWhere((e) => e.value == 1).key;

  /// Cell holding the highest milestone (the Black Hole) — the finish.
  int get blackHoleCell =>
      milestones.entries.firstWhere((e) => e.value == milestoneCount).key;

  static int edgeKey(int a, int b, int n) {
    final lo = a < b ? a : b;
    final hi = a < b ? b : a;
    return lo * n + hi;
  }

  bool hasWall(int a, int b) => walls.contains(edgeKey(a, b, cellCount));

  bool adjacent(int a, int b) {
    final dr = (rowOf(a) - rowOf(b)).abs();
    final dc = (colOf(a) - colOf(b)).abs();
    return dr + dc == 1;
  }

  // ── Generation ──────────────────────────────────────────────────────────────
  /// [force], when non-null, overrides level-based feature gating: exactly the
  /// listed features are inserted (empty set → a plain board). When null,
  /// features unlock by [level]. Used by the dev menu to test a given mechanic.
  static PuzzleGrid generate(int level, {Random? rng, Set<PuzzleFeature>? force}) {
    final r    = rng ?? Random();
    final size = (5 + level ~/ 3).clamp(5, 8);
    final n    = size * size;

    final wantWormhole = force?.contains(PuzzleFeature.wormhole)
        ?? (level >= kWormholeLevel);
    final wantGate = force?.contains(PuzzleFeature.massGate)
        ?? (level >= kMassGateLevel);
    final wantWell = force?.contains(PuzzleFeature.gravityWell)
        ?? (level >= kGravityWellLevel);

    var sol = _hamiltonian(size, r) ?? _snake(size);

    // ── Wormhole (skill-gated) ───────────────────────────────────────────────
    // Insert exactly one teleport by reversing the tail of the solution and
    // linking the cut point to the (former) last cell. The reversed tail stays
    // grid-adjacent throughout, so the new path covers every cell with all
    // consecutive steps grid-adjacent EXCEPT the single wormhole jump → still
    // solvable by construction, and the solution genuinely uses the wormhole.
    final wormholes = <int, int>{};
    final wormPositions = <int>{};   // solution indices the wormhole occupies
    bool adj(int a, int b) =>
        ((a ~/ size) - (b ~/ size)).abs() + ((a % size) - (b % size)).abs() == 1;
    if (wantWormhole && n >= 8) {
      for (var attempt = 0; attempt < 60; attempt++) {
        final cut = 1 + r.nextInt(n - 3);       // cut in [1, n-3]
        final a = sol[cut], b = sol[n - 1];
        if (adj(a, b)) continue;                // need a real (non-adjacent) jump
        sol = [
          ...sol.sublist(0, cut + 1),
          ...sol.sublist(cut + 1).reversed,
        ];
        wormholes[a] = b;
        wormholes[b] = a;
        wormPositions.addAll([cut, cut + 1]);   // a at cut, b at cut+1
        break;
      }
    }

    // Milestones: #1 pinned to the start, the Black Hole pinned to the LAST cell,
    // the rest at random increasing positions between. Capped so each milestone
    // is a distinct cosmic tier (Particle … Neutron Star, then Black Hole).
    final k = (4 + level ~/ 2).clamp(4, 7).clamp(2, n);
    final idxSet = <int>{0, n - 1};
    var guard = 0;
    while (idxSet.length < k && guard++ < 2000) {
      final p = 1 + r.nextInt(n - 2);
      if (!wormPositions.contains(p)) idxSet.add(p);  // keep portals milestone-free
    }
    final idx = idxSet.toList()..sort();
    final ms = <int, int>{};
    for (var i = 0; i < idx.length; i++) {
      ms[sol[idx[i]]] = i + 1;
    }

    // ── Mass gate + boson key (skill-gated) ──────────────────────────────────
    // Seal one solution edge behind a *boson* the player must collect first. The
    // boson is NOT a milestone, so it isn't picked up automatically by the forced
    // ascending order — it's an off-route fetch. We place the gate in the back
    // half of the solution and the boson somewhere before it, so following the
    // solution still works (key collected before the gate is crossed) → solvable
    // by construction, and the gate is a genuine routing detour.
    final gates = <int, int>{};   // edgeKey -> key id
    final keys  = <int, int>{};   // cell    -> key id
    final usedPos = <int>{...wormPositions, ...idx};  // positions off-limits to wells
    if (wantGate) {
      final msPos = idx.toSet();                 // milestone solution positions
      final gateCands = <int>[];                 // edge positions in the back half
      for (var p = (sol.length * 0.45).floor(); p + 1 < sol.length - 1; p++) {
        if (adj(sol[p], sol[p + 1])) gateCands.add(p);
      }
      if (gateCands.isNotEmpty) {
        final p = gateCands[r.nextInt(gateCands.length)];
        final keyCands = <int>[];                // positions before the gate
        for (var q = 1; q < p; q++) {
          if (msPos.contains(q) || wormPositions.contains(q)) continue;
          keyCands.add(q);
        }
        if (keyCands.isNotEmpty) {
          keyCands.sort();
          // Bias the boson earlier → a longer "go fetch it" dependency.
          final q = keyCands[r.nextInt((keyCands.length / 2).ceil())];
          gates[edgeKey(sol[p], sol[p + 1], n)] = 0;
          keys[sol[q]] = 0;
          usedPos.addAll([p, p + 1, q]);          // keep wells clear of the gate/boson
        }
      }
    }

    // ── Gravity well (skill-gated) ───────────────────────────────────────────
    // A well flings the worldline `wellRange` cells in a fixed direction. We
    // place it where the solution already runs straight for that many steps, so
    // the launch corridor is exactly the solution's next cells → guaranteed
    // clear when reached, and solvable by construction. The arrow telegraphs the
    // launch so the player aims their approach.
    final wells = <int, int>{};   // cell -> direction delta
    if (wantWell) {
      final cands = <int>[];      // solution start-indices of a straight run
      for (var i = 1; i + wellRange <= n - 2; i++) {
        final d = sol[i + 1] - sol[i];
        var straight = true;
        for (var s = 0; s < wellRange; s++) {
          if (sol[i + s + 1] - sol[i + s] != d || !adj(sol[i + s], sol[i + s + 1])) {
            straight = false; break;
          }
        }
        if (!straight) continue;
        // none of the well/corridor positions may overlap another feature
        if (List.generate(wellRange + 1, (s) => i + s).any(usedPos.contains)) continue;
        cands.add(i);
      }
      if (cands.isNotEmpty) {
        final i = cands[r.nextInt(cands.length)];
        wells[sol[i]] = sol[i + 1] - sol[i];
      }
    }

    // Walls on a fraction of edges the solution does NOT use. Only real grid
    // edges count — the wormhole jump isn't a grid edge, so skip it here.
    final solEdges = <int>{};
    for (var i = 0; i + 1 < sol.length; i++) {
      if (adj(sol[i], sol[i + 1])) solEdges.add(edgeKey(sol[i], sol[i + 1], n));
    }
    final walls = <int>{};
    for (var a = 0; a < n; a++) {
      final ra = a ~/ size, ca = a % size;
      if (ca < size - 1) {
        final key = edgeKey(a, a + 1, n);
        if (!solEdges.contains(key) && r.nextDouble() < 0.24) walls.add(key);
      }
      if (ra < size - 1) {
        final key = edgeKey(a, a + size, n);
        if (!solEdges.contains(key) && r.nextDouble() < 0.24) walls.add(key);
      }
    }

    return PuzzleGrid(
      size: size, solution: sol, milestones: ms, walls: walls,
      wormholes: wormholes, gates: gates, keys: keys, wells: wells);
  }

  /// Randomized Hamiltonian path via Warnsdorff's heuristic with random restarts.
  static List<int>? _hamiltonian(int size, Random rng) {
    final n = size * size;
    for (var attempt = 0; attempt < 400; attempt++) {
      final start   = rng.nextInt(n);
      final visited = List<bool>.filled(n, false);
      final path    = <int>[start];
      visited[start] = true;
      var cur = start;
      var stuck = false;
      while (path.length < n) {
        final nbrs = _neigh(cur, size).where((x) => !visited[x]).toList();
        if (nbrs.isEmpty) { stuck = true; break; }
        nbrs.shuffle(rng);
        nbrs.sort((a, b) => _countUnvisited(a, visited, size)
            .compareTo(_countUnvisited(b, visited, size)));
        cur = nbrs.first;
        visited[cur] = true;
        path.add(cur);
      }
      if (!stuck && path.length == n) return path;
    }
    return null;
  }

  static List<int> _neigh(int i, int size) {
    final r = i ~/ size, c = i % size;
    final o = <int>[];
    if (r > 0)        o.add(i - size);
    if (r < size - 1) o.add(i + size);
    if (c > 0)        o.add(i - 1);
    if (c < size - 1) o.add(i + 1);
    return o;
  }

  static int _countUnvisited(int i, List<bool> visited, int size) {
    var cnt = 0;
    for (final x in _neigh(i, size)) {
      if (!visited[x]) cnt++;
    }
    return cnt;
  }

  static List<int> _snake(int size) {
    final p = <int>[];
    for (var r = 0; r < size; r++) {
      if (r.isEven) {
        for (var c = 0; c < size; c++) p.add(r * size + c);
      } else {
        for (var c = size - 1; c >= 0; c--) p.add(r * size + c);
      }
    }
    return p;
  }
}
