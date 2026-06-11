# Singularity — Roadmap

The mechanic layer is **done** (core trace, wormholes, mass gates, gravity wells,
entangled pair, multiverse, Penrose skin, Syntropy mode). The **retention layer**
(Phase 2: badges, streak screen, freezes) and the **app icon** are done. The
**stakes layer** has begun: **Entropy mode** (high-score survival) shipped as Phase A
of the **Descent roguelike** — see `DESCENT.md`, now the marquee track.

Status legend: ☐ todo · ◐ partial · ✅ done

> **🚀 Active track — LAUNCH (`LAUNCH.md`).** Decision (post-2026-06): ship v1 first.
> The pre-launch focus is **pre-release polish + monetization (Phase 3) + progression
> menu (Phase 4)**, then deploy to Google Play + the Apple App Store. See `LAUNCH.md`
> for the full step-by-step store/accounts/website/Mac plan.

> **Post-launch feature update — Descent roguelike (`DESCENT.md`), DEFERRED.** A
> finite-act, branching entropy roguelike toward a final boss. Phase A (the entropy
> core) already shipped as **Entropy mode**. Phase B+ (run-state + map screen → DAG/
> relics → boss mechanics) is **parked until after launch** as a marquee content drop.

What remains before launch: **monetization**, **progression menu**, **pre-release
polish** (store name, dev-menu gating, readability, tuning), then the **store
deployment** itself.

---

## Phase 0 — Tuning & housekeeping (quick wins, pre-release hygiene)

Cheap changes that improve feel and tidy the project before any store push.

- ☐ **Multiverse difficulty/length pass.** Boards are ~70–72 cells (long) and the
  difficulty-sweep target (`_multiverseTarget`) is a first guess. Playtest 2- and
  3-board boards; tune cols/rows and the target so first encounters (L16/L26) feel
  guided, not punishing.
- ✅ **Quantum low-stage board size.** A multi-mechanic Quantum board now floors
  the generation level (→ board size) by how many mechanics it forces: 2 → ≥6×6,
  3 → ≥7×7, so combos reliably fit. Single-mechanic / plain boards stay small.
- ☐ **Entangled frequency tuning.** It now auto-spawns (~14%/level after 13);
  *needs on-device playtest* to confirm it doesn't feel too frequent/rare.
- ◐ **Multiverse difficulty/length.** Dimensions look good (per screenshots); the
  ~70-cell length + sweep target are *playtest-dependent* — hold until there's feel
  feedback rather than guessing.
- ✅ **Housekeeping:** deleted `design_bridge_options.html`; set a real
  `pubspec.yaml` `description`. (`· dev ·` menu kept for now — still needed for
  testing; gate/remove right before a public build.)

**Effort:** small. **Why first:** improves the experience everything else builds on.

---

## Phase 1 — Branding: app icon + name

Required before any store release; self-contained.

### App icon ✅
- **Done.** Procedural master art (`assets/icon/icon_render.html`, headless-rendered
  to `assets/icon/icon.png` + `icon_foreground.png`): a centered black hole with an
  orange accretion disk, purple event horizon, and a glowing gold worldline being
  consumed — matches the in-game motif. `flutter_launcher_icons` emits all Android
  densities + adaptive icon (foreground scaled into the safe zone, background
  `#04050a`) and the full iOS AppIcon set. Regenerate: re-render the HTML → re-run
  `dart run flutter_launcher_icons`.

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

- ✅ **Achievement badges per daily** (revamped from tiered medals) — collectible
  per-solve badges (a bitmask): PERFECT (no backtracks), UNAIDED (no solution peek),
  SWIFT (under par), BLAZING (under ½ par). Speed badges scale with board size so
  they stay earnable. Shown as chips in the collapse/share overlay + share text;
  `ProgressService` persists the per-day badge mask.
- ✅ **Streak screen** (revamped from the monthly star-map) — `StreakScreen` (home
  🔥 icon): big N-day-streak headline, the **current week** strip (check / freeze /
  missed), freeze tokens, a solves/current/best stat strip, and a horizontal ladder
  of **astrophysics-named milestone awards** (3 Photon · 5 Particle · 7 Asteroid ·
  31 Moon · 50 Planet · 100 Star · 150 Neutron Star · 200 Supernova · 250 Nebula ·
  300 Quasar · 365 Galaxy · 500 Singularity · 1000 Big Bang), achieved vs locked,
  with the next goal highlighted. `DailyService` now tracks max streak.
- ✅ **Streak-freeze token** — earn 1 every 7 consecutive days (cap 2); auto-consumed
  to bridge a missed day so the streak survives. `DailyService.markSolvedAndGetStreak`
  returns `(streak, freezes, freezeUsed, freezeEarned)`; surfaced in the collapse
  overlay ("STREAK SAVED · FREEZE USED" / "FREEZE EARNED") and the streak screen (❄ tokens).
  Four unit tests cover the streak/freeze logic.
- ☐ **Weekly Constellation set** — a 7-day themed run.
- ☐ **Month navigation** / a monthly calendar view (the streak screen is week-based).

**Effort:** medium–large (new screens + a progress service). **Dependencies:** none
hard; medals feed the share card and the star-map.

---

## Phase 3 — Monetization

The surfaces now exist; this wires the paywall.

- ☐ **`PremiumService`** — a persisted entitlement flag (dev toggle now, store
  purchase later via `in_app_purchase`).
- ☐ **Premium gating, candidates:**
  - **Syntropy picker** — free = a basic/preset Quantum; premium = full mechanic
    picker + timed toggle (the "tailor your session" pitch). *Already designed.*
  - **Penrose / future board themes** — cosmetic unlock (the `ThemeService` hook
    is already in place for this).
  - **Hint allowance** — the `HINT` button exists (next-few-steps reveal); free =
    N/day, premium = unlimited. Gate `_showHintSteps` behind a counter.
  - Optional: ad-free, extra daily replays, constellation packs.
- ☐ **Store/IAP plumbing** — `in_app_purchase`, product IDs, restore-purchases.

**Effort:** medium. **Dependencies:** cleanest after the Syntropy picker and themes
are the obvious value props (they are).

---

## Phase 4 — Progression menu / surface the unlock loop

Right now mechanic unlocks (`seen_*` flags → Field Guide → Syntropy picker) are
invisible in the main flow.

- ✅ **Home-screen progression strip** — the five mechanics as lit/dim icons + a
  "MECHANICS N/5 · NEXT · <name> · L<gate>" teaser, on the home screen above the
  footer; taps through to the Field Guide. Surfaces the unlock loop in the main flow.
- ✅ **Unlock celebration** — the first-encounter tutorial card now shows a
  "✦ NEW MECHANIC UNLOCKED ✦" banner (gold, glowing) for mechanic cards, with an
  unlock chime + haptic when a mechanic is first discovered.
- ☐ **Level-select / chapter view** (optional) — if infinity should become chaptered.
- ☐ Optional polish: a "deepest stage / solved count" stat on the strip.

**Effort:** medium. **Why later:** it dresses the systems Phases 2–3 establish.

---

## Phase 5 — Optional / bigger / later

- ☐ **Boss / escape mode** — the shelved *hunter* as a dedicated chase level where
  fill-every-cell doesn't apply (a separate mode, not a normal-puzzle addon).
- ◐ **Settings + audio** — `SettingsScreen` shipped (⚙ on Home): master sound
  on/off + a **classical music** picker (synthesized public-domain loops: Bach
  Prelude in C, Satie Gymnopédie No. 1, Chopin Prelude in A, Korobeiniki/Tetris,
  Bach Menuet BWV 814, Tchaikovsky Sugar Plum Fairy, plus a Bach Toccata/BWV 565
  *techno* remix with a synth-drum engine; Clair de Lune queued). Songs are
  enabled per-track in Settings and play in **random rotation, changing each
  level**; **separate SFX + music volume sliders** + a master mute; scoped to
  gameplay with a pause-menu toggle; pauses on app-background. Still open: a
  produced collapse-stinger sample, per-mode ambient intensity.
- ☐ **Penrose × multiverse combo** — currently Penrose is forced off in multiverse;
  compose the transforms if wanted.
- ☐ **Rectangular single-board variety** — the rectangular geometry now exists
  (multiverse uses it); could add wide single boards for variety.

---

## Suggested order (LAUNCH-focused)

Done so far: **Phase 0 (partial)**, **Phase 1 icon**, **Phase 2 retention**,
**Descent Phase A** (Entropy mode), **Phase 5 audio/Settings** (music system + ambient),
plus this session's entropy tuning, onboarding gate, Syntropy rename, guided HINT, and
the home readability pass.

**Now (pre-launch), per `LAUNCH.md`:**
1. **Register Apple + Google developer accounts** immediately (long lead times — the
   Google 14-day closed test + ID verification gate everything).
2. **Monetization (Phase 3)** — `PremiumService` + IAP gating (Syntropy picker /
   Penrose / HINT). *Needs a model decision first (one-time unlock vs other).*
3. **Progression menu (Phase 4)** — home progression + unlock celebration.
4. **Pre-release polish** — store-name decision, dev-menu gating, finish readability,
   AAB build, on-device tuning confirmation.
5. **Deploy** — store listings, privacy/support site, screenshots, closed test →
   production (both stores).

**Deferred to post-launch:** Descent Phase B+, plus Phase 2/5 extras (Constellation
set, hunter boss mode, Penrose×multiverse, wide single boards, Clair de Lune track).
