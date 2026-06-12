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
  main.dart          App entry, portrait lock, CollapseApp; loads Theme/Quantum services
  cosmic.dart        CosmicTier data class, kLowerTiers, kBlackHole, tierFor()
  puzzle_model.dart  PuzzleGrid: guaranteed-solvable generation + all rules
  puzzle_screen.dart PuzzleScreen StatefulWidget + _PuzzlePainter; all 3 modes live here
  home_screen.dart   Home menu (Daily / Entropy+difficulty / Quantum), top-bar toggles
  audio.dart         AudioService — procedural SoLoud engine
  field_guide.dart   GuideEntry/GuideService, tutorial cards, FieldGuideScreen + icons
  daily_service.dart Daily seed/level + streak + freeze tokens
  progress_service.dart Per-day daily badges + Entropy best score (per difficulty)
  streak_screen.dart StreakScreen — week strip, freezes, astrophysics milestone ladder
  theme_service.dart Persisted cosmetic board themes (Penrose 45° skin)
  quantum_setup.dart QuantumSetupScreen — tailor-your-session picker (types + timed)
  quantum_service.dart Persisted Quantum-mode config (chosen types, normal, timed)
  settings_screen.dart SettingsScreen — audio options (music picker + volume + sound)
  stats_service.dart Lifetime gameplay counters (solved/perfect/per-mechanic) → achievements
  achievements_screen.dart AchievementsScreen (🏆 on Home) — achievements + mechanics progression
test/
  widget_test.dart   Engine + medal/streak/freeze unit tests
```

**Docs:** `ROADMAP.md` (phased plan, ✅/◐/☐ status — the source of truth for "what's
next") and `DESCENT.md` (the Entropy/stakes design + the planned Descent roguelike).

---

## Core design rules

**Solvable-by-construction.** `PuzzleGrid.generate` builds the SOLUTION first
(random Hamiltonian path via Warnsdorff + snake fallback), then places milestones
along it and only adds walls to edges the solution doesn't use. Every generated
puzzle is always solvable — never touch the generation without re-running tests.

**Entangled Pair (quantum, force-only prototype).** A cosmic object in
superposition across two cells: `quantumCell` (ON the solution) and `ghostCell`
(OFF it). The solution covers every cell *except* the ghost, so `fillCount =
cellCount - 1`. Measuring one twin (tracing into it) collapses the other to a
void; `_collapsedCell` derives this from the path (so it reverts on undo) and the
collapsed cell is unsteppable. The two twins are **opposite checkerboard
colours**, so removing the on-path twin instead breaks the start/end parity →
that collapse is *provably* unsolvable. Right-choice deduction, solvable by
construction (a probe + widget test confirm: right branch always valid, wrong
branch always parity-dead). Win/black-hole checks use `grid.fillCount`, not
`cellCount`. **Graduated into progression:** forced on the first-encounter level
`kEntangledLevel`=13, then ~14% per level above; also forceable via the dev menu
(`PuzzleFeature.entangled`). It's exclusive (reshapes the solution) and **suppresses
the additive mechanics** when present (`!wantEntangled` gates wormhole/gate/well).

**Difficulty-authored generation.** Difficulty ≈ *branching*, not board size:
fewer walls → more open → harder (more choices); more walls → more forced →
easier. `PuzzleGrid.difficulty` (a `_branching` proxy: excess legal moves along
the solution) measures it. Generation sweeps wall density (best-of-14) and keeps
the set whose difficulty is closest to `_difficultyTarget(level)` (a smooth ramp,
`6 + (level-1)*3.1`, clamped by the board's achievable range). Result: difficulty
ramps *within* a board size as the level climbs, and is far more consistent
(spread ~2–6 vs ~8–17 before). The widget test asserts the ramp.

**Black Hole is the finish.** Milestone 1 (Particle) is pinned to the solution's
first cell; the top milestone (Black Hole) is pinned to the LAST cell. The rule
engine only allows entering the Black Hole when it is the final remaining cell
(`path.length == cellCount - 1`). This is the core fix over the prototype.

**Audio (`lib/audio.dart`).** Hybrid engine on `flutter_soloud` (4.x, standard
`ffiPlugin` — CMake/podspec, builds on the existing CI unchanged). Haptics are
kept and layered with sound. `AudioService` is a singleton, inited fire-and-forget
in `main()` and **fails silently** if the engine is unavailable (never blocks the
game). All sounds are synthesised procedurally into in-memory PCM WAV and played
through a global Freeverb send for a cosmic space:

- **Milestone ladder** — each consumed cosmic object plays an ascending major-
  pentatonic bell (`milestone(n)`), so a full solve plays a little melody.
- **Step tick** — quiet blip per cell, pitch brightening with path progress.
- **Denied** — soft dissonant low tone on the black-hole-early nudge.
- **Collapse** — layered stinger (sub-bass implosion → boom + flash burst at
  ~0.8s → inharmonic shimmer tail) synced to the 2 s collapse animation. This is
  the designed "impact one-shot" slot: to swap in a produced sample, drop a file
  in `assets/audio/` and load it in `_buildSounds` via `_soloud.loadAsset(...)`.
- **Ambient pad** — a seamless 8 s low cosmic hum (all partials loop-locked to
  1/dur). **App-wide:** `startAmbient()` is called once from `AudioService.init()`
  (and on unmute) and runs everywhere — the **main menu** and all gameplay — at a
  fixed `_padTarget` (0.30), ducked to half under any active soundtrack. It's
  `setPause`d (not stopped) when backgrounded, and stopped only by mute. Screens no
  longer start/stop it (it's not per-`PuzzleScreen` anymore).
- **Bridge** (`bridge()`) — deep rising sweep into a bright emergence chord, for a
  multiverse bridge crossing (distinct from the wormhole `warp()`).
- **Mute** — toggle on the home screen, persisted via `shared_preferences`
  (`audio_muted`); `AudioService.muted` is honoured by every play call.
- **Music** (classical soundtrack) — a **random rotation** of public-domain pieces,
  **synthesized** like everything else (no audio assets, no recording licensing):
  each piece is note data (`_MusicPiece`/`_Note`) rendered by `_renderPiece` through
  the voices (`_addVoice` + the electronic `_add*`) into **one seamlessly-looping
  buffer** — each note's decaying tail **wraps around** the buffer end (modular
  indexing) so the loop has no click/gap/tempo-drift. Tracks are **lazily**
  synthesized + cached (`_music` map) and **duck the ambient pad** to `_padTarget*0.5`.
  **Rotation model:** the player chooses which tracks are **enabled** (`_enabledMusic`
  set, persisted `music_enabled`; defaults to all) in Settings; `_pickTrack()` plays a
  random enabled one and `nextTrack()` rotates to a *different* one **on every
  level-up** (called from `_newPuzzle(advance:)`). In **Settings** each row taps two
  ways: tap-to-**preview** (`previewTrack(id)` force-plays that track regardless of
  the enabled set, highlighting the row while it's `currentTrack`) and a **checkbox**
  to toggle rotation membership (`setEnabled`). **Scoped to gameplay, not the
  menu:** plays only while a *music context* is active — `PuzzleScreen` / the Settings
  preview call `enterMusicContext()`/`exitMusicContext()`. `_musicShouldPlay` is the
  single gate (`ready && !muted && !backgrounded && musicOn && context && enabled
  non-empty`). The **pause menu** MUSIC ON/OFF flips `_musicOn` (`setMusicOn`,
  persisted `music_on`) — a quick mute separate from the enabled set.
  **Separate volumes:** `_sfxVolume` (every SFX play multiplies by it) and
  `_musicVolume`, persisted (`sfx_volume`/`music_volume`), each its own slider in
  Settings; the master **mute** (home/pause/Settings) still kills everything.
  **Backgrounding:** `AudioService` is a `WidgetsBindingObserver` —
  `didChangeAppLifecycleState` `setPause`s the pad + music handles on paused/hidden,
  resumes on resumed. **Future hook:** tracks could be unlock-gated (achievement /
  premium) — gate `kMusicTracks` entries in the Settings checklist. Catalogue =
  `kMusicTracks` (`MusicTrack` id→title→composer),
  each id mapped to a builder in `_pieceFor`. Per-piece voice envelope on
  `_MusicPiece` (melody/bass decay + ring): plucky music-box (Bach) vs legato
  (Satie). **Shipped:** Bach — Prelude in C (BWV 846, mm. 1–4, I→ii⁷→V⁷→I
  arpeggio); Satie — Gymnopédie No. 1 (Gmaj7↔Dmaj7 vamp + verified main phrase);
  Chopin — Prelude in A, Op. 28 No. 7 (bars 1–4, the E7→A mazurka gesture);
  Korobeiniki (the Tetris Type-A folk theme, A minor, melody only); Bach — Menuet
  from French Suite No. 3, BWV 814 (bars 1–8, two voices — the source of GB
  Tetris "Music B"); Tchaikovsky — Dance of the Sugar Plum Fairy (celesta theme,
  E minor, 16-beat A-section — written for celesta, so the music-box voice is the
  *authentic* timbre; melody −1 octave, the two cascading answers kept low).
  Pitches verified against public-domain sources — Mutopia LilyPond (relative-octave
  parsed, or converted to MIDI deterministically via a throwaway Dart tool for the
  dense Menuet), and a public-domain MIDI parsed to its top line (Sugar Plum). No
  hand-transcription. **Toccata · Techno** — Bach's BWV 565 opening flourish (MIDI-
  verified) reimagined as **techno**: this is why `_Note` carries an `_Instr` voice
  (celesta · bass · lead · sub · kick · hat · clap), not just a `bass` bool. The
  classical voices go through `_addVoice`; the electronic ones have dedicated
  synthesis (`_addLead` detuned-saw, `_addSub` punchy sub, `_addKick` pitch-drop +
  click, `_addHat`/`_addClap` noise) — a four-on-the-floor groove under the Bach
  lead, the global reverb giving it a dub-techno space. To add a *genre* track,
  reuse those `_Instr` voices in a builder. **Planned:** Debussy Clair de Lune
  (rubato — doesn't reduce cleanly to a beat grid). On-theme nod: GB Tetris "Music B" was a
  chiptune Bach minuet. Chosen via the **Settings screen** (`settings_screen.dart`,
  ⚙ tune icon on Home).

Keep everything procedural/asset-free unless deliberately adding a designed
sample (then update this doc). The reverb setup is wrapped in its own try/catch
so a filter hiccup never costs the dry audio.

**Tutorial & Field Guide (`lib/field_guide.dart`).** First-encounter teaching:
the first time the player meets the Core, a Wormhole, a Mass Gate, a Gravity Well,
an Entangled Pair, or a Multiverse — **and on the first Entropy board**
(`seen_entropy`, predicate `_isEntropy`) **and the first Syntropy board**
(`seen_syntropy`, predicate `_isQuantum`), the two mode explainers — `PuzzleScreen`
shows a one-time modal card (`_buildTutorialCard`, queued in `_cards`) over the
dimmed board; "GOT IT" dismisses and marks it seen. State is persisted via
`GuideService` (`seen_core/_wormhole/_gate/_well/_entangled/_multiverse/_entropy/
_syntropy`) — the mechanic flags drive the **Field Guide** (`FieldGuideScreen`, book
icon top-left on Home): every concept/object is listed, but un-encountered entries
are blacked out showing "UNLOCKS AT LEVEL X" (the mechanic's skill-gate level; the
`seen_entropy`/`seen_syntropy` mode cards are card-only, not guide entries).
**Onboarding gate:** Daily & Syntropy are **locked on Home** ("PLAY ENTROPY FIRST")
until `seen_core && seen_entropy` — i.e. the player has played Entropy once and
dismissed the worldline + entropy cards (`_onboarded` in `home_screen`). To add a
mechanic: append to `kGuideEntries`
(+ `kTutorialCards` if it deserves a card) and add a motif to `_GuideIconPainter`.
The old transient "NEW · …" hint intros were replaced by these cards; `_showHint`
is now only for in-context nudges (blocked moves).

**Board themes — Penrose skin (`lib/theme_service.dart`).** A cosmetic toggle
that tilts the whole board **+45° into a diamond** (scaled `1/√2` to stay
inscribed in its box), so the axis-aligned grid becomes a lattice of **45° light
cones** and the worldline reads as a null-ray path — a Penrose/spacetime diagram
crunching toward the singularity. Purely visual: generation, rules, and
solvability are untouched (all 7 tests still pass). Implementation is two-sided
and must stay in sync:
- **Render:** `_PuzzlePainter` wraps *only the board content* in a
  rotate(π/4)+scale(1/√2) about board centre (nested inside the collapse
  transform); the HUD and the collapse celebration draw in screen space and stay
  upright. The collapse implosion + celebration pivot on the **rotated** black-hole
  position (`pivot`), not the raw cell centre, or the region crunches to the wrong
  spot.
- **Input:** `_boardLocal` inverse-transforms every gesture point (un-rotate −π/4,
  un-scale ×√2) before hit-testing, so taps land on the cell you *see*. Touches in
  the diamond's outer corners map outside the grid → ignored.
Persisted like mute (`ThemeService.penrose`, key `penrose_theme`), loaded in
`main()`, toggled by the diamond icon on the home screen (top-right, left of
mute). Forward-looking: this is the hook an **unlockable perk** (via play or
monetization, TBD) would gate — flip `ThemeService.setPenrose` from wherever the
unlock lands.

**Syntropy mode (`lib/quantum_setup.dart`, `lib/quantum_service.dart`).** Displayed to
players as **SYNTROPY** (the order-from-disorder counterpart to Entropy mode; renamed
from "Quantum Mode" to avoid colliding with the *quantum*/entangled mechanic). The
**display name only** changed — the enum value, files, service, and field names stay
`quantum`/`PuzzleMode.quantum` to avoid churn (grep `SYNTROPY` for the player-facing
strings). The old Zen mode (`PuzzleMode.zen`) became this *tailor-your-session*
mode. A setup screen (`QuantumSetupScreen`, reached from the home "SYNTROPY" button)
lets the player choose **which game types appear** (Normal + the five mechanics) and
whether the run is **TIMED or RELAXED**. Only **unlocked** types are selectable — locked
ones are greyed with "UNLOCK AT LEVEL X" (uses the same `GuideService` `seen_*` flags as
the Field Guide, so the unlock loop drives players back into Infinity/Daily). Each Quantum
board is a random pick from the chosen set (`PuzzleScreen._newPuzzle`: builds a per-board
`force` set — an empty set = a plain board; exclusive mechanics come alone; multiverse gets
a random 2/3 boards). Level still advances for difficulty; `_timed` (`!_isQuantum ||
quantumTimed`) gates the timer display + ambient calm + share-card time. Config persists via
`QuantumService` (`quantum_features`/`quantum_normal`/`quantum_timed`), loaded in `main()`.
First open pre-selects all unlocked types. **Premium hook:** the picker is the natural
paywall surface — gate entry to `QuantumSetupScreen` behind a purchase flag when
monetization lands (no gate yet).

**The three modes (`PuzzleMode`).**
- **Daily** — date-seeded board (`DailyService.todaySeed`), timed, shareable; earns
  badges + drives the streak.
- **Entropy** (was "Infinity"; `PuzzleMode.entropy`) — endless **high-score survival**.
  See below.
- **Syntropy** (display name; internally `PuzzleMode.quantum`) — the customizable
  safe haven (above); no stakes.

**Entropy mode (high-score survival).** A run-wide **entropy meter** (`_entropy`, 0..1)
is the fail state. It **rises** on a passive interval tick and on mistakes
(`_addEntropy`: backtrack/hint/solution costs — so PERFECT/UNAIDED play is survival
skill); **solving vents it** and **scores** the board (`base + level + clean + speed`,
× difficulty multiplier 1.0/1.3/1.7). Fill the bar mid-board → **HEAT DEATH** overlay
(score + best + NEW RUN). All magnitudes live in **`_ent()`** — a single per-difficulty
record `(tick, step, vent, backtrack)`, all `// TUNE`. The **vent is a relief, not a
reset** (smaller than a board's typical passive rise), so entropy **gently creeps up**
over a run — it's a survival clock, and the yellow/red audio cues are actually
reachable (an earlier over-large vent kept the bar near 0, so the cues never fired).
**Easy** stays forgiving — clean fast solves keep it low, slow/deep play drifts up
(14 s tick · 0.036 step · 0.10 vent · 0.028 backtrack); **Medium** (10 / 0.048 / 0.14 /
0.040) creeps with normal play; **Hard** climbs fast (7 / 0.062 / 0.16 / 0.050). Depth
gently shortens the tick (`baseTick − level~/7`, floored). Hint/solution costs are the
globals `_kEntHint`/`_kEntSolution`.
**Difficulty unlock ladder:** Easy is always open; **Medium unlocks at Easy Lv 16**,
**Hard at Medium Lv 16** (`_kUnlockLevel`=16). Max level reached per difficulty is
tracked by `ProgressService.recordLevel`/`bestLevel` (`entropy_maxlevel_<diff>`,
recorded each level-advance in `_newPuzzle`); the home chips lock/grey accordingly,
show the next-unlock hint, and fall back to Easy if a remembered locked tier is chosen.
Best score is per-difficulty (`ProgressService.bestEntropy/recordEntropy`). Daily &
Quantum have **no** entropy.
**HUD bar & cues:** `_entropyBar()` is a prominent 300×18 meter that glows/breathes
(via `_pulse`) once in the yellow/red band and flips its label to "HEAT DEATH" with a
warning icon at ≥80%. All entropy changes go through **`_setEntropy()`**, which fires a
one-shot audio cue when the meter *crosses up* a band — `AudioService.entropyWarn()`
(soft two blips, ~50%) / `entropyDanger()` (low sour pulse, ~80%) — tracked by
`_entBand`; venting back down re-arms them.

**Daily meta-progression.**
- **Badges** (`ProgressService`, per-day bitmask) — collectible per-solve achievements:
  PERFECT (no backtracks), UNAIDED (no hint/solution), SWIFT (under par), BLAZING
  (under ½ par; par = `cells*1.7`). Shown as chips in the collapse/share overlay.
- **Streak + freezes** (`DailyService`) — `markSolvedAndGetStreak` returns
  `(streak, freezes, freezeUsed, freezeEarned)`; earn 1 freeze / 7 days (cap 2),
  auto-spent to bridge a missed day. Tracks max streak.
- **`StreakScreen`** (home ✨ icon) — current-week strip, freeze tokens, stat strip,
  and the astrophysics **milestone ladder** (3 Photon … 1000 Big Bang).

**HINT button (`_showHintSteps`) — guided.** Finds the longest prefix of the
player's path that still matches `grid.solution`, **erases the stray part of the
worldline back to that last-correct cell** (snapping before any `_atomic` move it
would split, like `_truncateTo`), highlights the next ~3 correct cells (a pulsing
connector from the head + brightest ring on the immediate step), and **locks input
to the first cell** (`_hintTarget`): in `_onPan`, while a hint is up, only that cell
may be stepped — so the hint persists (no auto-clear) and clears *exactly* when the
correct move is made. Pressing HINT again dismisses it (no charge); undo/reset/
backtrack clear it via `_clearHint()` (which now clears `_hintCells`+`_hintTarget`).
Works with every mechanic because `solution[t]` is always the steppable *entry* of
any atomic move (wormhole/well/bridge), and `_onPan` runs the atomic jump on entry —
the test *"hint: every solution step is reachable for all mechanics"* asserts every
consecutive solution step is `linked`. Forfeits UNAIDED + costs entropy per new hint.
**Premium hook:** gate hint count later. Distinct from the full **SOLUTION** reveal
(`_toggleSolution`).

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

## Input & feedback

- **Drag** to trace. Forward stepping is edge-to-edge responsive (no deadzone) —
  keep it that way; a deadzone on forward motion makes swiping feel sticky.
- **Drag back** onto the previous cell undoes the last step — but only when the
  finger reaches the cell's interior (`_deepInside`, `_undoMargin = 0.34`). This
  gates *only the undo*, so a fast swipe grazing the previous cell's edge won't
  trigger a spurious backtrack while drawing stays fluid.
- **Undo** / **Reset** live in a labelled control bar below the board (using the
  lower dead space); Undo steps back one, Reset clears to the start cell.
- **Pause** (top-right) freezes the timer and input and drops a fully-opaque
  overlay that blocks the board (resume / mute / home). **Mute** is also in the
  top bar (in-game), mirroring the home-screen toggle and the persisted setting.
- **Tap any visited cell** to rewind the worldline to it (`_truncateTo`) — the
  fast fix for an early mistake without dragging all the way back.
- **Black-hole-early feedback:** attempting to enter the Black Hole before the
  region is fully consumed is no longer silently rejected — it fires
  `_nudgeBlackHole()` (heavy haptic + expanding red ring + the in-context hint
  "CONSUME EVERY CELL FIRST"), throttled to once per ~700ms.

## Special mechanics (additive to the core puzzle)

Each is sparse (≤1 per board), skill-gated, solvable-by-construction, and gets a
one-time `NEW · …` intro hint (persisted via `seen_wormhole` / `seen_gate`).
`PuzzleGrid.generate(level, {force})` gates by level unless `force` (a
`Set<PuzzleFeature>`) overrides it — `null` = auto by level, `{}` = none, e.g.
`{PuzzleFeature.massGate}` = force that mechanic. This is what the **dev menu**
(home screen "· dev ·" → NORMAL / WORMHOLE / MASS GATE / GRAVITY WELL /
ENTANGLED PAIR / MULTIVERSE / ALL (NO QUANTUM)) uses to launch a board with a chosen mechanic
via `PuzzleScreen(forceFeatures:, fixedLevel:)`.

- **Wormhole pairs** (`wormholes`, level ≥ `kWormholeLevel` = 4): two linked
  cells; the worldline steps between twins. Built by reversing the tail of the
  Hamiltonian solution and linking the cut point to the former last cell.
  Rendered as teal swirling portals; the worldline lifts the pen across the jump;
  `_warp` flashes on traversal (whoosh via `AudioService.warp()`).
- **Mass gates + boson keys** (`gates`: edgeKey → keyId; `keys`: cell → keyId;
  level ≥ `kMassGateLevel` = 7): an edge sealed until you collect its **boson**
  (a green collectible that is NOT a milestone, so the forced ascending order
  doesn't grab it for free — it's an off-route fetch). The gate goes in the back
  half of the solution and the boson before it, so the solution collects the key
  first → solvable by construction, and the gate is a real routing detour. (The
  earlier milestone-keyed version was pointless: ascending order always satisfied
  it.) `_canStep` blocks until `_keyCollected(keyId)`; collecting the boson fires
  `AudioService.unlock()` + the `_unlock` open-ripple; `_nudgeGate` → "GATE · GRAB
  THE BOSON FIRST". Drawn green (boson = mote + spark, gate = bar: solid locked,
  faint open). `_nudgeKind` (1 black hole · 2 gate · 3 well) routes the bump-flash.

- **Gravity wells** (`wells`: cell → direction delta, `wellRange` = 2, level ≥
  `kGravityWellLevel` = 10): stepping onto a well flings the worldline `wellRange`
  cells in a fixed direction, auto-consuming the corridor. Placed where the
  solution already runs straight for `wellRange` steps → the launch corridor is
  the solution's own next cells, guaranteed clear when reached → solvable by
  construction. `_canStep` only accepts the well if `_wellCorridorClear`; entering
  launches via `_wellPath` and records the move in `_atomic` (start-index →
  cells added) so **undo is atomic** (the whole fling unwinds, not one corridor
  cell — drag-back through a launch is disabled, Undo handles it; `_truncateTo`
  snaps to before the well).
  Blocked launch → `_nudgeWell`. Drawn magenta (swirl + arrow + landing dots);
  `slingshot()` audio + `_sling` launch streak.

## Collapse animation

`_solve` (2000ms) drives a staged collapse in `_PuzzlePainter._drawCollapse`:
implosion (board scales toward the black hole) → white flash → zoom-out where
the region shrinks to a point and a deterministic starfield is revealed (the
"this region was one star in a galaxy" beat), with purple shockwave rings and a
lingering new star at the singularity.

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

## Shipped mechanics (summary)

All four additive mechanics are implemented and dev-menu testable:

| Mechanic | Level gate | Force flag | Status |
|---|---|---|---|
| Wormhole pairs | ≥ 4 | `PuzzleFeature.wormhole` | ✅ shipped |
| Mass gates + bosons | ≥ 7 | `PuzzleFeature.massGate` | ✅ shipped |
| Gravity wells | ≥ 10 | `PuzzleFeature.gravityWell` | ✅ shipped |
| Entangled pair | 13 (forced) then ~14%/lvl | `PuzzleFeature.entangled` | ✅ shipped, graduated |
| Multiverse | 16 (forced 2-board) · 26 (forced 3-board) · then ~12%/lvl | `PuzzleFeature.multiverse` | ✅ shipped, graduated |

**Multiverse (stacked boards + bridges)** — in progress. **Phases 1–2 shipped** (engine
+ render/input/dev-menu; playable via dev menu → MULTIVERSE).
`PuzzleFeature.multiverse` (exclusive; graduated — `kMultiverseLevel`=16 forced 2-board,
`kMultiverse3Level`=26 forced 3-board, then ~12%/level; also dev-menu forceable)
generates **two stacked square boards** (5×5) woven by one continuous worldline that
crosses **bridges** between them. `PuzzleGrid` is now N-board-general: cell index =
`board*size² + local`; `boardOf/rowOf/colOf` are board-aware, `adjacent` requires the
same board, `cellCount = size²·boardCount`. A `Bridge(a, b, oneWay)` is a cross-board
teleport — `oneWay` true = Einstein–Rosen (enter black mouth `a`, eject white mouth
`b`, no return; `b` is entry-blocked via `isBridgeEntryBlocked`), false = a traversable
wormhole crossable either way (`bridgeExitFrom` honours direction). Generation
(`_generateMultiverse`) is **cut-and-interleave**: Hamiltonian-cover each board, splice
as A₁→bridge→B→bridge→A₂ → one path covering all 2N cells with exactly two cross-board
jumps, guaranteed ≥1 one-way + ≥1 two-way (a there-and-back weave) → solvable by
construction. Walls are per-board on unused in-board edges. Two widget tests assert it.
**Phase 2 (render/input):** the board area becomes a vertical *stack* of both boards,
laid out by `_BoardLayout` (shared by painter + input so hit-testing never drifts);
the painter's `center()`/backdrop/grid/walls are board-aware, the worldline lifts the
pen across the gap at a bridge, and bridges draw as two-way teal portals or one-way
black-mouth→white-hole pairs (both distinct from the finish black hole). `_canStep`/
`_onPan` cross a bridge as an atomic teleport (one-way fires only from the black mouth;
white mouths are entry-blocked). Penrose is forced off in multiverse (combo deferred).
**Phase 3a (N boards):** generation is now **hub-and-spoke** — board 0 (the hub) is split
into `boardCount` arcs and each other board (a "spoke") is fully covered between hub arcs
(A₁ S₁ A₂ S₂ … Aₙ), with 2·(boardCount−1) bridges → covers all cells, ≥1 one-way + ≥1
two-way, solvable by construction. Generalises the 2-board A→B→A weave. Hub cut points are
≥2 apart (a 1-cell interior arc would be both a landing and the next mouth — degenerate).
Board count: 2 or 3, via `generate(multiverseBoards:)` (dev menu MULTIVERSE ×2 / ×3) or
~45% random when unset. Boards are **rectangular (wider than tall)** to use the horizontal
space and spread bridge mouths out: `rows × cols` = 5×7 (2 boards) / 4×6 (3 boards).
`PuzzleGrid.size` = rows, `boardCols` = cols (null ⇒ square for single-board); `cols`,
`_na`, `rowOf/colOf/cellCount/_neighG` are cols-aware (identical to before when square).
Multiverse generation uses rectangular Hamiltonian helpers (`_hamiltonianRect/_snakeRect/
_neighRect`); the square helpers are untouched for single-board. `_BoardLayout` is
rows×cols-aware (shared by painter + input). Each universe has a signature colour
(gold/azure/rose, `_universeColor`) on its border + panel wash;
worldline legs are coloured by the universe they **departed from**, and each **bridge mouth
is coloured by the universe it leads TO** (so clustered portals are told apart by
destination).
**Phase 3b:** dedicated bridge audio (`AudioService.bridge()` / `_bridgeWhoosh` — a deep
rising sweep into a bright emergence chord, distinct from the wormhole warp), and a
first-encounter tutorial card + Field Guide entry (`seen_multiverse`, id `multiverse`,
unlock level `kMultiverseLevel`; motif = two stacked panels linked by a portal).
**Phase 3c (graduation + difficulty):** multiverse and the entangled pair now **enter
normal progression** (`generate` auto-gating): entangled forced at L13 then ~14%/level;
multiverse forced 2-board at L16 and 3-board at L26, then ~12%/level (board count random
2/3 once both unlocked). Both are exclusive — multiverse early-returns to its own
generator; entangled suppresses the additive mechanics. Multiverse walls now use a
**difficulty sweep** (best-of-12 density vs `_multiverseTarget(level, boards)`, a gentle
board-count-scaled ramp) instead of a fixed density. Targets/probabilities are tunable by
playtest. **Multiverse mechanic complete.**

**Hunter mechanic** — shelved. Proven incompatible with fill-every-cell: on every
Hamiltonian path the player must eventually visit the hunter's cell, making a
"safe" route impossible regardless of hunter period. Viable only as a separate
escape/boss mode (not a normal-puzzle addon).

---

## Current state & next steps  →  see `ROADMAP.md` and `DESCENT.md`

**`ROADMAP.md` is the source of truth** for what's done (✅/◐/☐) and next. Snapshot
as of this writing:

- **Done:** all puzzle mechanics; Penrose skin; Quantum mode; app icon; **Phase 2
  retention** (badges, StreakScreen, freezes); **Entropy mode** (high-score survival
  with the entropy meter + Easy/Medium/Hard, per the `DESCENT.md` design); the HINT
  button.
- **Active big track — Descent roguelike (`DESCENT.md`):** the entropy core (Phase A)
  shipped *as* Entropy mode. **Next = Phase B**: the Descent run skeleton (run-state +
  a linear act → final boss + a map screen), then branching DAG + relics + boss
  mechanics (Heat Death / Big Crunch / Kerr Spin / Final Singularity).
- **Also pending:** **on-device tuning** — Entropy balance (the `kEntropy*` / tick
  constants), multiverse length/difficulty, entangled frequency; **Phase 3
  monetization** (`PremiumService` gating the Quantum picker / Penrose theme / HINT
  count — all hooks exist); **Phase 4** progression-menu / unlock surfacing; the
  **name decision** (store title) and gating/removing the `· dev ·` menu before release.

**Android signing** — ✅ DONE. Keystore at `android/collapse-release.jks`
   (git-ignored). GitHub secrets set: KEYSTORE_BASE64, KEY_STORE_PASSWORD,
   KEY_PASSWORD (`NT2FltZM5SGXKhaYKgYg`), KEY_ALIAS (`collapse`). CI builds
   release-signed APKs; `--build-number=${{ github.run_number }}` increments
   versionCode each push. Backup at `~/collapse-signing/`. **Keep the keystore
   backed up — losing it blocks Play Store updates.**
