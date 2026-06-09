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
enum PuzzleFeature { wormhole, massGate, gravityWell, entangled, multiverse }

/// Levels below these never spawn the feature — they unlock as skill gates so
/// players meet them only after the basic trace is second nature.
const int kWormholeLevel    = 4;
const int kMassGateLevel    = 7;
const int kGravityWellLevel = 10;
const int kMultiverseLevel  = 16;   // placeholder skill-gate (force-only MVP)

/// A cross-board teleport link between two boards of a [multiverse] puzzle —
/// an Einstein–Rosen / wormhole bridge. [oneWay] true → only [a]→[b] may be
/// initiated (a black-hole mouth feeding a white-hole exit; the exit can't be
/// entered normally). false → a *traversable* wormhole the worldline may cross
/// either way. The mechanic is built on mixing both kinds on one puzzle.
class Bridge {
  final int  a;        // initiating mouth (global cell index)
  final int  b;        // exit mouth      (global cell index, on another board)
  final bool oneWay;
  const Bridge(this.a, this.b, this.oneWay);
}

class PuzzleGrid {
  final int size;                 // square board: size × size
  final List<int> solution;       // a Hamiltonian path (cell indices, in order)
  final Map<int, int> milestones; // cellIndex -> milestone number (1..k)
  final Set<int> walls;           // blocked edges, encoded via [edgeKey]
  final Map<int, int> wormholes;  // symmetric cell<->twin links (teleport edges)
  final Map<int, int> gates;      // edgeKey -> key id that opens it
  final Map<int, int> keys;       // cell -> key id (the "boson" collectible)
  final Map<int, int> wells;      // cell -> direction delta (gravity-well launch)
  final int quantumCell;          // entangled twin ON the solution (-1 if none)
  final int ghostCell;            // entangled twin OFF the solution (vanishes)
  final int boardCount;           // stacked boards (1 = normal; >1 = multiverse)
  final List<Bridge> bridges;     // cross-board teleport links (multiverse)

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
    this.quantumCell = -1,
    this.ghostCell = -1,
    this.boardCount = 1,
    this.bridges = const [],
  });

  /// Launch direction delta for the well on [cell], or null.
  int? wellDir(int cell) => wells[cell];

  /// This board has an entangled pair (two superposed cells; one vanishes).
  bool get hasQuantum => ghostCell >= 0;
  bool isQuantum(int cell) => hasQuantum && (cell == quantumCell || cell == ghostCell);
  int  quantumTwin(int cell) =>
      cell == quantumCell ? ghostCell : (cell == ghostCell ? quantumCell : -1);

  /// Cells that must be filled to win. With an entangled pair, exactly one twin
  /// is measured and the other vanishes, so it's one fewer than [cellCount].
  int get fillCount => cellCount - (hasQuantum ? 1 : 0);

  bool isWormhole(int cell)   => wormholes.containsKey(cell);
  int? wormholeTwin(int cell) => wormholes[cell];

  /// Key id required to cross the edge a–b, or null if no gate there.
  int? gateKeyAt(int a, int b) => gates[edgeKey(a, b, cellCount)];
  /// Key id of the boson on [cell], or null.
  int? keyIdAt(int cell)        => keys[cell];

  /// Two cells are linked if grid-adjacent, a wormhole pair, or a bridge pair.
  bool linked(int a, int b) {
    if (adjacent(a, b) || wormholes[a] == b) return true;
    for (final br in bridges) {
      if ((br.a == a && br.b == b) || (br.a == b && br.b == a)) return true;
    }
    return false;
  }

  /// If stepping onto [cell] initiates a bridge crossing, the exit cell; else
  /// null. A one-way bridge can only be initiated from its [Bridge.a] mouth.
  int? bridgeExitFrom(int cell) {
    for (final br in bridges) {
      if (br.a == cell) return br.b;
      if (br.b == cell && !br.oneWay) return br.a;
    }
    return null;
  }

  /// A one-way bridge's exit mouth can't be entered by a normal step (a white
  /// hole: arrival-only); it is filled solely by the crossing that lands on it.
  bool isBridgeEntryBlocked(int cell) {
    for (final br in bridges) {
      if (br.oneWay && br.b == cell) return true;
    }
    return false;
  }

  bool get hasMultiverse => boardCount > 1;

  int get cellCount      => size * size * boardCount;
  int get milestoneCount => milestones.length;

  int get _na => size * size;             // cells per board
  int boardOf(int i) => i ~/ _na;
  int rowOf(int i) => (i % _na) ~/ size;
  int colOf(int i) => (i % _na) % size;

  /// In-board grid neighbours of [cell] as global indices (never crosses boards).
  List<int> _neighG(int cell) {
    final base = boardOf(cell) * _na, li = cell % _na;
    final r = li ~/ size, c = li % size;
    final o = <int>[];
    if (r > 0)        o.add(base + li - size);
    if (r < size - 1) o.add(base + li + size);
    if (c > 0)        o.add(base + li - 1);
    if (c < size - 1) o.add(base + li + 1);
    return o;
  }

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

  /// Difficulty proxy: total "excess branching" along the solution — at each
  /// step, how many legal moves the player faced beyond the single correct one.
  /// 0 = fully forced (trivial); higher = more choices to reason through. More
  /// walls lower it; an open board raises it.
  int get difficulty => boardCount == 1
      ? _branching(solution, milestones, walls, size)
      : _branchingMulti();

  /// Board-aware branching for multiverse boards: in-board legal moves at each
  /// step, plus any available bridge crossing (a non-local extra option).
  int _branchingMulti() {
    final cc = cellCount;
    final visited = List<bool>.filled(cc, false);
    var msSeen = 0, branch = 0;
    for (var i = 0; i + 1 < solution.length; i++) {
      final head = solution[i];
      visited[head] = true;
      if (milestones.containsKey(head)) msSeen++;
      var opts = 0;
      for (final nb in _neighG(head)) {
        if (visited[nb]) continue;
        if (walls.contains(edgeKey(head, nb, cc))) continue;
        final m = milestones[nb];
        if (m != null) {
          if (m != msSeen + 1) continue;
          if (m == milestoneCount && i + 1 != solution.length - 1) continue;
        }
        opts++;
      }
      final bx = bridgeExitFrom(head);
      if (bx != null && !visited[bx]) opts++;
      if (opts > 1) branch += opts - 1;
    }
    return branch;
  }

  static int _branching(List<int> sol, Map<int, int> ms, Set<int> walls, int size) {
    final n  = size * size;
    final mc = ms.length;
    final visited = List<bool>.filled(n, false);
    var msSeen = 0, branch = 0;
    for (var i = 0; i + 1 < sol.length; i++) {
      final head = sol[i];
      visited[head] = true;
      if (ms.containsKey(head)) msSeen++;
      var opts = 0;
      for (final nb in _neigh(head, size)) {
        if (visited[nb]) continue;
        if (walls.contains(edgeKey(head, nb, n))) continue;
        final m = ms[nb];
        if (m != null) {
          if (m != msSeen + 1) continue;                 // out-of-order milestone
          if (m == mc && i + 1 != sol.length - 1) continue; // black hole only last
        }
        opts++;
      }
      if (opts > 1) branch += opts - 1;
    }
    return branch;
  }

  bool hasWall(int a, int b) => walls.contains(edgeKey(a, b, cellCount));

  bool adjacent(int a, int b) {
    if (boardOf(a) != boardOf(b)) return false;   // different boards never touch
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

    // Multiverse reshapes the board into stacked sheets, so it's its own path
    // (force-only MVP, exclusive — never combined with the single-board mechanics).
    if (force?.contains(PuzzleFeature.multiverse) ?? false) {
      return _generateMultiverse(level, r);
    }

    final size = (5 + level ~/ 3).clamp(5, 8);
    final n    = size * size;

    final wantWormhole = force?.contains(PuzzleFeature.wormhole)
        ?? (level >= kWormholeLevel);
    final wantGate = force?.contains(PuzzleFeature.massGate)
        ?? (level >= kMassGateLevel);
    final wantWell = force?.contains(PuzzleFeature.gravityWell)
        ?? (level >= kGravityWellLevel);
    // Entangled pair is force-only for now (its own deduction mode).
    final wantEntangled = force?.contains(PuzzleFeature.entangled) ?? false;

    var sol = _hamiltonian(size, r) ?? _snake(size);

    // ── Entangled pair (force-only) ──────────────────────────────────────────
    // One cosmic object in superposition across two cells. The solution covers
    // every cell EXCEPT the off-path "ghost" twin (which vanishes when the other
    // is measured). The two twins are opposite checkerboard colours, so removing
    // the ON-path twin instead would break the start/end parity → that collapse
    // is provably unsolvable. Right-choice deduction, solvable by construction.
    var quantumCell = -1, ghostCell = -1;
    if (wantEntangled) {
      int colour(int c) => ((c ~/ size) + (c % size)) % 2;
      for (var t = 0; t < 80 && ghostCell < 0; t++) {
        final b = r.nextInt(n);
        final s = _hamiltonianExcluding(size, b, r);
        if (s == null) continue;
        final cands = s
            .where((c) => c != s.first && c != s.last && colour(c) != colour(b))
            .toList();
        if (cands.isEmpty) continue;
        sol = s;
        ghostCell = b;
        quantumCell = cands[r.nextInt(cands.length)];
      }
    }

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
    // is a distinct cosmic tier (Particle … Neutron Star, then Black Hole). Uses
    // sol.length (= n, or n-1 when an entangled twin is excluded).
    final slen = sol.length;
    final qPos = quantumCell >= 0 ? sol.indexOf(quantumCell) : -1;
    final k = (4 + level ~/ 2).clamp(4, 7).clamp(2, slen);
    final idxSet = <int>{0, slen - 1};
    var guard = 0;
    while (idxSet.length < k && guard++ < 2000) {
      final p = 1 + r.nextInt(slen - 2);
      if (!wormPositions.contains(p) && p != qPos) idxSet.add(p);
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

    // ── Difficulty-authored walls ────────────────────────────────────────────
    // Walls go only on edges the solution doesn't use. Fewer walls → more open →
    // harder (more choices); more walls → more forced → easier. We sweep wall
    // density and keep the set whose branching-difficulty is closest to the
    // level's target, so difficulty ramps by cleverness and stays consistent
    // within a board size — not just by board growth.
    final solEdges = <int>{};
    for (var i = 0; i + 1 < sol.length; i++) {
      if (adj(sol[i], sol[i + 1])) solEdges.add(edgeKey(sol[i], sol[i + 1], n));
    }
    final target = _difficultyTarget(level);
    var walls = <int>{};
    var bestErr = 1 << 30;
    const attempts = 14;
    for (var a = 0; a < attempts; a++) {
      final density = 0.45 - a * (0.41 / (attempts - 1));   // 0.45 → 0.04
      final cand = _buildWalls(solEdges, density, size, n, r);
      final err  = (_branching(sol, ms, cand, size) - target).abs();
      if (err < bestErr) { bestErr = err; walls = cand; if (err == 0) break; }
    }
    // Keep the ghost twin reachable so the (wrong) choice is actually available.
    if (ghostCell >= 0) {
      walls.removeWhere((key) => key ~/ n == ghostCell || key % n == ghostCell);
    }

    return PuzzleGrid(
      size: size, solution: sol, milestones: ms, walls: walls,
      wormholes: wormholes, gates: gates, keys: keys, wells: wells,
      quantumCell: quantumCell, ghostCell: ghostCell);
  }

  /// Multiverse board (force-only MVP): two stacked square boards woven by one
  /// continuous worldline that crosses bridges between them.
  ///
  /// Construction is "cut-and-interleave": cover board A and board B each with a
  /// Hamiltonian path, then splice them as A₁ → (bridge) → B → (bridge) → A₂, so
  /// the single path covers every cell of both boards with all in-board steps
  /// grid-adjacent and exactly two cross-board jumps → always solvable by
  /// construction. One bridge is one-way (Einstein–Rosen: enter the black mouth,
  /// eject the white, no return), the other two-way (a traversable wormhole) —
  /// guaranteeing the mix the mechanic is built around, and a there-and-back weave.
  static PuzzleGrid _generateMultiverse(int level, Random r) {
    const size  = 5;
    const na    = size * size;        // cells per board
    const total = 2 * na;             // cellCount

    final a      = _hamiltonian(size, r) ?? _snake(size);        // board 0 (local)
    final bLocal = _hamiltonian(size, r) ?? _snake(size);        // board 1 (local)
    final b      = bLocal.map((c) => c + na).toList();           // board 1 (global)

    // Cut board A so the worldline leaves after A₁, fills B, returns for A₂.
    // i in [1, na-3] keeps the global start (a[0]) and finish (a[na-1]) off the
    // four bridge mouths.
    final i = 1 + r.nextInt(na - 3);

    final sol = <int>[
      ...a.sublist(0, i + 1),   // A₁ = a[0..i]      (ends at mouth a[i])
      ...b,                     // B  = b[0..na-1]   (land a[i]→b[0]; leave at b[na-1])
      ...a.sublist(i + 1),      // A₂ = a[i+1..na-1] (land b[na-1]→a[i+1]; end at finish)
    ];

    // Two bridges; exactly one one-way and one two-way (the mix, guaranteed).
    final firstOneWay = r.nextBool();
    final bridges = <Bridge>[
      Bridge(a[i],      b[0],      firstOneWay),    // A → B  (after A₁)
      Bridge(b[na - 1], a[i + 1], !firstOneWay),    // B → A  (after B)
    ];

    // Milestones: #1 at the global start, Black Hole at the global end, the rest
    // spread across both boards — never on a bridge mouth.
    final mouthPos = {i, i + 1, i + na, i + na + 1};   // mouth positions in sol
    final slen = sol.length;                            // == total
    final k = (4 + level ~/ 2).clamp(4, 7);
    final idxSet = <int>{0, slen - 1};
    var guard = 0;
    while (idxSet.length < k && guard++ < 4000) {
      final p = 1 + r.nextInt(slen - 2);
      if (!mouthPos.contains(p)) idxSet.add(p);
    }
    final idx = idxSet.toList()..sort();
    final ms = <int, int>{};
    for (var m = 0; m < idx.length; m++) {
      ms[sol[idx[m]]] = m + 1;
    }

    // Walls only on in-board edges the solution doesn't use (per board), so the
    // solution stays wall-free → solvable. Bridges aren't grid edges. Moderate
    // fixed density for the MVP (difficulty-authored sweep is a later pass).
    bool adjG(int x, int y) {
      if (x ~/ na != y ~/ na) return false;
      final lx = x % na, ly = y % na;
      return ((lx ~/ size) - (ly ~/ size)).abs() +
             ((lx %  size) - (ly %  size)).abs() == 1;
    }
    final solEdges = <int>{};
    for (var s = 0; s + 1 < sol.length; s++) {
      if (adjG(sol[s], sol[s + 1])) solEdges.add(edgeKey(sol[s], sol[s + 1], total));
    }
    const density = 0.18;
    final walls = <int>{};
    for (var board = 0; board < 2; board++) {
      final base = board * na;
      for (var c = 0; c < na; c++) {
        final rr = c ~/ size, ccol = c % size, gc = base + c;
        if (ccol < size - 1) {
          final key = edgeKey(gc, gc + 1, total);
          if (!solEdges.contains(key) && r.nextDouble() < density) walls.add(key);
        }
        if (rr < size - 1) {
          final key = edgeKey(gc, gc + size, total);
          if (!solEdges.contains(key) && r.nextDouble() < density) walls.add(key);
        }
      }
    }

    return PuzzleGrid(
      size: size, boardCount: 2, solution: sol, milestones: ms, walls: walls,
      bridges: bridges);
  }

  /// Target branching-difficulty for a level — a smooth ramp. Best-of-N walls
  /// aim at this; the achievable range is naturally clamped by the board size.
  static int _difficultyTarget(int level) => (6 + (level - 1) * 3.1).round();

  static Set<int> _buildWalls(
      Set<int> solEdges, double density, int size, int n, Random r) {
    final walls = <int>{};
    for (var a = 0; a < n; a++) {
      final ra = a ~/ size, ca = a % size;
      if (ca < size - 1) {
        final key = edgeKey(a, a + 1, n);
        if (!solEdges.contains(key) && r.nextDouble() < density) walls.add(key);
      }
      if (ra < size - 1) {
        final key = edgeKey(a, a + size, n);
        if (!solEdges.contains(key) && r.nextDouble() < density) walls.add(key);
      }
    }
    return walls;
  }

  /// A Hamiltonian path covering every cell EXCEPT [blocked] (n-1 cells), via
  /// the same Warnsdorff heuristic. Used for the entangled pair's solution.
  static List<int>? _hamiltonianExcluding(int size, int blocked, Random rng) {
    final n = size * size;
    for (var attempt = 0; attempt < 400; attempt++) {
      final start = rng.nextInt(n);
      if (start == blocked) continue;
      final visited = List<bool>.filled(n, false);
      visited[blocked] = true;                 // exclude the ghost cell
      final path = <int>[start];
      visited[start] = true;
      var cur = start;
      var stuck = false;
      while (path.length < n - 1) {
        final nbrs = _neigh(cur, size).where((x) => !visited[x]).toList();
        if (nbrs.isEmpty) { stuck = true; break; }
        nbrs.shuffle(rng);
        nbrs.sort((a, b) => _countUnvisited(a, visited, size)
            .compareTo(_countUnvisited(b, visited, size)));
        cur = nbrs.first;
        visited[cur] = true;
        path.add(cur);
      }
      if (!stuck && path.length == n - 1) return path;
    }
    return null;
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
