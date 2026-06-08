# Singularity: Collapse — Claude Code Project Guide

A standalone Zip-style cosmic puzzle game. Drag one continuous worldline that
consumes cosmic objects in ascending mass order — Particle → Asteroid → Moon →
Planet → Star → Neutron Star → Black Hole — while filling every cell of the
region. The Black Hole is always the final cell: reaching it collapses the region
into a larger stage.

Extracted from the Singularity arcade game after the core trace proved fun.

---

## Stack

| Layer   | Detail |
|---------|--------|
| Flutter | 3.44 stable, Dart 3.12 |
| Target  | Android (signed APK) + iOS (unsigned IPA via GitHub Actions) |
| No game engine — pure Flutter canvas + CustomPainter | |

---

## Repo

`https://github.com/SympathyForTheDevil/singularity_collapse`
Branch: `main`. Push after every working feature.
Same PAT as the arcade game (fine-grained, scoped to this repo).

---

## File layout

```
lib/
  main.dart          App entry, portrait lock, CollapseApp
  cosmic.dart        CosmicTier data class, kLowerTiers, kBlackHole, tierFor()
  puzzle_model.dart  PuzzleGrid: guaranteed-solvable generation + all rules
  puzzle_screen.dart PuzzleScreen StatefulWidget + _PuzzlePainter CustomPainter
test/
  widget_test.dart   Engine unit tests (solvability, endpoint pinning, wall rules)
```

---

## Core design rules

**Solvable-by-construction.** `PuzzleGrid.generate` builds the SOLUTION first
(random Hamiltonian path via Warnsdorff + snake fallback), then places milestones
along it and only adds walls to edges the solution doesn't use. Every generated
puzzle is always solvable — never touch the generation without re-running tests.

**Black Hole is the finish.** Milestone 1 (Particle) is pinned to the solution's
first cell; the top milestone (Black Hole) is pinned to the LAST cell. The rule
engine only allows entering the Black Hole when it is the final remaining cell
(`path.length == cellCount - 1`). This is the core fix over the prototype.

**No audio yet.** Haptics only (selectionClick per step, lightImpact on milestone,
heavyImpact on solve). Audio is a planned addition; avoid adding native plugins
without updating this doc and the CI workflow.

**Portrait only.** Locked in `main.dart`. Do not add landscape.

**No state management library.** Plain `StatefulWidget` + `setState`. Keep it that
way unless the codebase grows meaningfully beyond one screen.

---

## Cosmic tier ladder

| # | Object      | Color      | Notes                      |
|---|-------------|------------|----------------------------|
| 1 | Particle    | #88ccff    | Start cell, smallest orb   |
| 2 | Asteroid    | #b08858    |                            |
| 3 | Moon        | #cccccc    |                            |
| 4 | Planet      | #44aaff    |                            |
| 5 | Star        | #ffcc33    |                            |
| 6 | Neutron Star| #99eeff    |                            |
| — | Black Hole  | #bb55ff    | Always the final milestone |

Milestone count per puzzle: 4–7 depending on level. `tierFor(n, count)` maps
milestone number to tier; the top milestone always maps to Black Hole.

---

## Puzzle rules (`_canStep`)

A cell is steppable iff:
1. It is grid-adjacent to the current head.
2. No wall blocks the edge.
3. It has not been visited (no revisiting).
4. If it is a milestone, its number == milestones_visited_so_far + 1 (ordered).
5. If it is the Black Hole (final milestone), `path.length == cellCount - 1` —
   it can only be entered as the absolute last move.

Drag back onto the previous cell to undo the last step.

---

## Build & commit workflow

```powershell
Set-Location "C:\Users\adame\ClaudeProjects\singularity_collapse"
& "C:\Users\adame\flutter\bin\flutter.bat" build apk --release

git add <files>
Set-Content -Path commit_msg.txt -Value $msg -Encoding ascii
git commit -F commit_msg.txt
Remove-Item commit_msg.txt
git push origin main
```

Or bash heredoc:
```bash
git commit -F - <<'EOF'
Subject line

Body.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
```

---

## CI (`.github/workflows/build.yml`)

Triggers on push to `main`. Builds APK (ubuntu) + unsigned IPA (macos).
Updates the rolling `latest-build` prerelease with both binaries.

Android signing is **optional**: set these secrets for a signed APK; omit them
for an unsigned (debug-signed) fallback that still installs fine for testing.

| Secret             | What                              |
|--------------------|-----------------------------------|
| `KEYSTORE_BASE64`  | base64-encoded `collapse-release.jks` |
| `KEY_STORE_PASSWORD` | keystore password               |
| `KEY_PASSWORD`     | key password                      |
| `KEY_ALIAS`        | key alias                         |

---

## Planned next features (priority order)

1. **Unique mechanics** — mass gates (only enter after reaching milestone N),
   wormhole pairs (enter one, path continues from the twin), gravity-well tiles
   (momentum lock: forces next move in a fixed direction), hunter enemy.
2. **Daily seed** — date-seeded daily puzzle (same board for everyone), streak,
   clipboard share card.
3. **Audio** — procedural tones on milestone absorption, a stage-up sting on
   collapse. Avoid asset files; keep everything procedural.
4. **Menu / level select** — a proper home screen with solved-count display
   and level progression indicators.
5. **Android signing** — generate `collapse-release.jks`, set the four CI
   secrets, update `android/app/build.gradle.kts` signing config.
