# Singularity — Roadmap

The mechanic layer is largely **done** (core trace, wormholes, mass gates, gravity
wells, entangled pair, multiverse, Penrose skin, Quantum mode). What remains is the
**meta layer** (retention, monetization, progression), **branding/release prep**
(app icon, name), and a **tuning/housekeeping** pass. Sequenced below by leverage.

Status legend: ☐ todo · ◐ partial · ✅ done

---

## Phase 0 — Tuning & housekeeping (quick wins, pre-release hygiene)

Cheap changes that improve feel and tidy the project before any store push.

- ☐ **Multiverse difficulty/length pass.** Boards are ~70–72 cells (long) and the
  difficulty-sweep target (`_multiverseTarget`) is a first guess. Playtest 2- and
  3-board boards; tune cols/rows and the target so first encounters (L16/L26) feel
  guided, not punishing.
- ☐ **Quantum low-stage board size.** Early Quantum stages are 5×5, so additive
  combos (wormhole+gate+well) don't always fit. Option: give Quantum a roomier
  floor (e.g. start size ≥6) so chosen mechanics reliably appear.
- ☐ **Entangled frequency tuning.** It now auto-spawns (~14%/level after 13);
  confirm it doesn't feel too frequent/rare.
- ☐ **Housekeeping:** delete `design_bridge_options.html` (scratch); gate or remove
  the `· dev ·` menu before a public build; set a real `pubspec.yaml` `description`.

**Effort:** small. **Why first:** improves the experience everything else builds on.

---

## Phase 1 — Branding: app icon + name

Required before any store release; self-contained.

### App icon ☐
- **Concept:** a black hole with an orange accretion disk and a single glowing
  worldline curling into it — matches the in-game motif and the procedural aesthetic.
- **Approach:** generate a 1024×1024 master PNG (can be produced procedurally via a
  headless-render of a Canvas/SVG, consistent with how we mocked the bridge diagram),
  then add the `flutter_launcher_icons` dev-dependency to emit all Android/iOS sizes.
  Adaptive icon for Android (foreground = orb+worldline, background = deep space).
- **Touch-points:** `pubspec.yaml` (icon config), generated `mipmap-*` / iOS
  `AppIcon.appiconset`.

### Name decision ◐ — "Singularity" vs "Singularity: Collapse"
- **For dropping "Collapse":** punchier, one word; the home screen *already* uses
  "SINGULARITY" as the wordmark (with "COLLAPSE" as a small subtitle).
- **Against:** "Singularity" alone is heavily contested on app stores (a 2010 FPS +
  many apps), hurting discoverability and trademark distinctiveness. "Collapse" is
  also thematically core (regions *collapse* into the black hole).
- **Recommendation:** keep the visual wordmark "**SINGULARITY**" (already in place),
  but retain a distinguishing **store title** — e.g. "Singularity: Collapse" or a
  fresh tagline ("Singularity — a cosmic puzzle"). Decide the *store* name separately
  from the *in-app* wordmark.
- **If renaming the display name:** change `MaterialApp.title`, Android
  `android:label`, iOS `CFBundleDisplayName`/`CFBundleName`, the in-game header
  ("COLLAPSE · STAGE"), and the home subtitle. The Dart package/folder name
  (`singularity_collapse`) is internal — leave it to avoid churn.

**Effort:** icon = small–medium (mostly art); name = a decision + a few string edits.

---

## Phase 2 — Retention / meta-progression  ⭐ highest engagement leverage

The engagement engine. Builds on the existing `DailyService` (streak, daily seed).

- ☐ **Par + medals per daily** — Bronze = solve, Silver = under par time, Gold =
  no backtracks. Track per-day result; show on the daily and the share card.
- ☐ **Star-map constellation** — each daily solve lights a star in a monthly grid;
  a finished month = a named constellation. A new home-screen surface and a
  `ProgressService` (persisted per-day medal map).
- ☐ **Streak-freeze token** — one "miss a day" forgiveness; earned or granted.
  Extends `DailyService` streak logic.
- ☐ **Weekly Constellation set** — a 7-day themed run.

**Effort:** medium–large (new screens + a progress service). **Dependencies:** none
hard; medals feed the share card and the star-map.

---

## Phase 3 — Monetization

The surfaces now exist; this wires the paywall.

- ☐ **`PremiumService`** — a persisted entitlement flag (dev toggle now, store
  purchase later via `in_app_purchase`).
- ☐ **Premium gating, candidates:**
  - **Quantum picker** — free = a basic/preset Quantum; premium = full mechanic
    picker + timed toggle (the "tailor your session" pitch). *Already designed.*
  - **Penrose / future board themes** — cosmetic unlock (the `ThemeService` hook
    is already in place for this).
  - Optional: ad-free, extra daily replays, constellation packs.
- ☐ **Store/IAP plumbing** — `in_app_purchase`, product IDs, restore-purchases.

**Effort:** medium. **Dependencies:** cleanest after the Quantum picker and themes
are the obvious value props (they are).

---

## Phase 4 — Progression menu / surface the unlock loop

Right now mechanic unlocks (`seen_*` flags → Field Guide → Quantum picker) are
invisible in the main flow.

- ☐ **Home-screen progression** — current stage, next unlock teaser ("Wormholes at
  L4"), solved count.
- ☐ **Unlock celebration** — a small "NEW MECHANIC UNLOCKED" beat the first time a
  mechanic graduates into play (ties into the existing tutorial-card system).
- ☐ **Level-select / chapter view** (optional) — if infinity should become chaptered.

**Effort:** medium. **Why later:** it dresses the systems Phases 2–3 establish.

---

## Phase 5 — Optional / bigger / later

- ☐ **Boss / escape mode** — the shelved *hunter* as a dedicated chase level where
  fill-every-cell doesn't apply (a separate mode, not a normal-puzzle addon).
- ☐ **Settings + audio** — a settings screen (volume, SFX/music sliders); a produced
  collapse-stinger sample; per-mode ambient intensity.
- ☐ **Penrose × multiverse combo** — currently Penrose is forced off in multiverse;
  compose the transforms if wanted.
- ☐ **Rectangular single-board variety** — the rectangular geometry now exists
  (multiverse uses it); could add wide single boards for variety.

---

## Suggested order

**0 (tuning/housekeeping) → 1 (icon + name) → 2 (retention) → 3 (monetization) →
4 (progression menu) → 5 (optional).**

Rationale: Phase 0 is cheap polish; Phase 1 is release-prerequisite branding;
Phase 2 is the single biggest driver of whether players come back; Phase 3 monetizes
the now-rich feature set; Phase 4 makes the whole progression legible; Phase 5 is
upside.
