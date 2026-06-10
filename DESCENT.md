# Design — Entropy, high-score Infinity, and the Descent roguelike

The puzzle layer is deep; this is the **stakes layer**. A fill-puzzle can't be
"unsolvable", so the fail state comes from a run-wide resource — **entropy** —
not from the board. Three modes now have distinct identities:

| Mode | Identity | Stakes |
|---|---|---|
| **Quantum** | Customizable safe haven — pure puzzle fun | none (no entropy, no fail) |
| **Infinity** | Endless high-score survival | entropy; fill the bar → run over |
| **Descent** | Finite-act roguelike toward a final boss | entropy + choices + relics |

---

## 1. Entropy (the shared core)

A meter in `[0, 1]` — the Second Law as a health bar (on-theme: the game is about
collapse). It **rises** and **vents**; hitting `1.0` ends the run.

**Rises:**
- a **live trickle** while a board is unsolved, rate scaling with depth (the clock
  you race);
- **+chunk per backtrack** (undo / reset / tap-rewind / drag-back) — so the
  PERFECT/UNAIDED badges become survival resources;
- **+chunk for a Hint, larger for a full Solution peek** (assistance has a price —
  also the monetization overlap).

**Vents:**
- **solving a board** (a relief pulse; clean + fast vents more);
- **Refuge nodes** / relics (Descent only).

All magnitudes are tunable constants (`kEntropy*`), flagged `// TUNE` — first pass
is a guess; calibrate by playtest.

---

## 2. Infinity = Endless Entropy  *(build first)*

The current Infinity (easy→hard, no fail) becomes a **high-score survival run**:

- One continuous run: solve boards back-to-back, level (difficulty + size) climbs.
- Entropy trickles up while you solve (faster each level) and jumps on mistakes;
  **solving vents it**. Solve fast and clean to stay ahead.
- **Fill the bar before you finish a board → the region collapses → run over.**
- **Score** accrues per board: `base + level + clean bonus + speed bonus`. Depth ×
  quality. Persisted **best score**; shown on the game-over screen + home.
- Restart is one tap — chase a better score.

UI: an **entropy bar** + a **score** in the HUD; a **game-over overlay**
("HEAT DEATH" / final score / best / RESTART).

---

## 3. Descent = the roguelike  *(later phase)*

A run = traverse a branching **DAG map** through finite **acts**, each capped by a
**boss**, beat the final boss to **win** — then **Ascension** levels for endless
score. Entropy carries across the whole run.

### Node types
- **Standard** — a board with a random mechanic modifier.
- **Elite** — harder board, better reward.
- **Refuge** — vent entropy, no puzzle (the calm beat).
- **Anomaly** — a risk/reward *choice* (e.g. "cross the unstable bridge: +relic,
  +entropy").
- **Cache** — pick 1 of 3 relics.
- **Boss** — a unique set-piece (below).

Each node is just a `PuzzleGrid.generate(level, force:, multiverseBoards:)` config,
so the puzzle layer is free; the new work is the **run state**, **map screen**,
**relics**, **scoring/unlocks**, and the **boss mechanics**.

### Relics (run modifiers)
Stabilizer (1 free backtrack/board) · Dark Energy (entropy slowly decays) ·
Exotic Matter (one-way bridges become two-way) · Tachyon (+1 free hint/board) ·
Observer Effect (flash the solution 1s at start) · …plus **curses** at risk nodes.

### Scoring & the restart hook
`score = depth × difficulty + clean (badge) bonuses + speed + bosses felled`.
**Win** = final boss down. **Ascension** raises difficulty for higher multipliers;
**relic/starter unlocks** per run. That's the loop that makes you restart.

---

## 4. Boss mechanics (new set-pieces)

Bosses justify one-off spectacle mechanics (still solvable-by-construction):
- **Heat Death** — cells decay into walls on a countdown; fill them in time.
- **The Big Crunch** — the board collapses inward ring by ring; fill outside-in.
- **Kerr Spin** (frame-dragging) — movement curves into a forced orbit near the core.
- **Multiverse Nexus** — max 3-board weave, many mixed bridges.
- **The Final Singularity** — a huge board fusing several mechanics: the run's exam.

---

## 5. Build phases

- **Phase A — Infinity Entropy** *(now):* entropy meter + live trickle + backtrack/
  hint costs + solve vent + score + game-over + best-score persistence + HUD bar.
  Quantum & Daily untouched (no entropy). Validates the whole entropy feel cheaply.
- **Phase B — Descent skeleton:** run-state model, a simple linear act → boss, the
  map screen, win/lose flow (reusing the entropy core).
- **Phase C — Branching DAG + relics + Cache/Anomaly/Refuge nodes.**
- **Phase D — Boss mechanics** (decay, crunch, spin) + the Final Singularity.
- **Phase E — Ascension + meta-unlocks + leaderboard polish.**
