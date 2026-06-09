# Singularity: Collapse

A cosmic Hamiltonian-path puzzle game built in Flutter.

Drag one continuous **Timeline** through a region of space. Consume cosmic objects
in ascending mass order — Particle → Asteroid → Moon → Planet → Star → Neutron
Star → Black Hole — while filling every cell. The Black Hole is always the final
move: reaching it collapses the region into a larger one.

---

## Gameplay

- **One verb:** drag a continuous, non-crossing worldline.
- **Ordered consumption:** cosmic objects must be collected in ascending mass order.
- **Fill every cell:** every cell in the region must be visited before the Black
  Hole can be entered.
- **Undo / truncate:** drag back to undo one step, or tap any visited cell to
  rewind to that point instantly.

### Additive mechanics (unlocked by level)

| Mechanic | Description | Unlocks |
|---|---|---|
| **Wormhole** | Two linked portals. Enter one and your line emerges from the twin — mandatory teleport. | Level 4 |
| **Mass Gate + Boson** | A sealed barrier. Collect its off-route Boson key first to open it. | Level 7 |
| **Gravity Well** | Step on it and you're flung a fixed distance in a fixed direction — no choice. | Level 10 |
| **Entangled Pair** | A cosmic object in superposition across two cells. Measure one and its twin collapses to a void. Exactly one choice keeps the region solvable. | Level 13 |

All mechanics are **solvable by construction** — every generated puzzle has a
guaranteed solution regardless of which mechanic is active.

---

## Modes

| Mode | Description |
|---|---|
| **Today's Region** | A date-seeded daily puzzle — the same board for everyone. Streak tracked. |
| **Infinity Mode** | Endless procedural puzzles with a live timer. Difficulty ramps by level. |
| **Zen Mode** | Endless puzzles, no timer. |

---

## Stack

| Layer | Detail |
|---|---|
| Framework | Flutter 3.44 / Dart 3.12 |
| Rendering | Pure `CustomPainter` — no game engine |
| Audio | `flutter_soloud` 4.x — fully procedural PCM synthesis + Freeverb reverb |
| Target | Android (release-signed APK) + iOS (unsigned IPA) |
| CI | GitHub Actions — builds APK + IPA on every push to `main` |

---

## Architecture

```
lib/
  main.dart          App entry, portrait lock
  cosmic.dart        CosmicTier data class, tier ladder constants
  puzzle_model.dart  PuzzleGrid: solvable-by-construction generation + all rules
  puzzle_screen.dart PuzzleScreen + _PuzzlePainter CustomPainter
  audio.dart         AudioService singleton (procedural synthesis, Freeverb)
  field_guide.dart   Tutorial cards, Field Guide screen, GuideService persistence
  home_screen.dart   Home screen, mode buttons, dev launcher, mute toggle
  daily_service.dart Date-seeded puzzle seed, streak persistence
test/
  widget_test.dart   Engine unit tests (solvability, gating, parity, difficulty ramp)
```

### Core design invariants

- **Solvable by construction.** Generation builds the solution first (Warnsdorff
  Hamiltonian path), places milestones along it, then adds walls only to edges the
  solution does not use. Mechanics are layered onto the solution path — never
  against it.
- **Difficulty by branching, not board size.** A `_branching` proxy measures
  excess legal moves along the solution; a best-of-14 wall-density sweep keeps
  each puzzle's difficulty close to `6 + (level-1) × 3.1`. Difficulty ramps
  *within* a board size as the level climbs.
- **Atomic undo.** Multi-cell moves (wormhole teleport, gravity-well launch) are
  tracked in `_atomic: Map<int,int>` and unwind as a single undo step.
- **Entangled pair parity proof.** The two twins are placed on opposite
  checkerboard colours. Removing the ghost twin preserves parity; removing the
  on-path twin breaks it → that collapse is *provably* unsolvable. A 300-seed
  probe and widget test confirm: right-branch valid 300/300, wrong-branch
  parity-dead 300/300.

---

## Building

```powershell
# Debug
flutter run

# Release APK
flutter build apk --release

# Release IPA (macOS only)
flutter build ipa
```

Android release signing reads from `android/key.properties` (local) or CI
environment secrets (GitHub Actions). See CLAUDE.md for signing details.

---

## Repository

`https://github.com/SympathyForTheDevil/singularity_collapse`  
Branch: `main`. CI builds a rolling `latest-build` prerelease on every push.
