# Singularity: Collapse — Ruthless Design Review

> A no-punches-pulled product/design review of the game in its current state.
> Reviewed against the live codebase: `puzzle_model.dart`, `puzzle_screen.dart`,
> `cosmic.dart`, `daily_service.dart`, `home_screen.dart`.

---

## What this game actually is (and the central problem)

**This is LinkedIn's "Zip" puzzle with a cosmic skin.** Mechanically, it's a
Hamiltonian-path constraint puzzle: drag one line, hit numbered checkpoints in
order, fill every cell, respect walls. The "cosmic mass ladder" (Particle →
Asteroid → … → Black Hole) is **pure cosmetic relabeling of numbered dots 1–7**.
Nothing merges. Nothing accretes. No mass is simulated. The Black Hole "collapse"
is a ring animation, not a mechanic.

The single most important sentence in this review:

> **Your theme promises emergence, growth, and physics. Your mechanic delivers
> deterministic constraint-satisfaction. The fantasy and the gameplay are at war.**

When a player sees "Singularity: Collapse," cosmic objects, a mass ladder, and a
black hole, their brain primes for *Suika* — accretion, snowballing, satisfying
physical merges, escalating chaos. What they get is a logic line-puzzle with one
correct answer. That gap is why this will feel hollow after the novelty wears off,
and it's the root cause of almost every problem below.

Balatro, Vampire Survivors, and Suika are **run-based emergent-chaos games. This
is a deterministic single-solution puzzle**, in the family of Sudoku, Picross,
Flow Free, and Zip. Those puzzle games are real businesses — but they retain and
monetize *completely differently*, and they do **not** produce "one more run"
adrenaline. They produce "one more puzzle" calm. The tension is resolved in
Section 11.

---

## 1. Core Gameplay Loop

**Immediately understandable?** Yes — the game's biggest genuine strength.
Zip-likes onboard themselves.

**Fun in first 30 seconds?** Mildly. Drawing a glowing line that fills cells is
tactile and the worldline render is genuinely pretty. But the first puzzle is a
5×5 with 4 milestones — solvable in ~10 seconds with almost no thought. First
impression is "pleasant," not "wow."

**Fun after 30 minutes?** Declining. **Infinite procedurally-generated Hamiltonian
puzzles have no authored difficulty curve and no "aha" design.** Yours are random
Warnsdorff paths with milestones dropped at *random* increasing indices
(`puzzle_model.dart:69`) and walls sprinkled at a flat 24% (`:88`). That produces
puzzles with no personality — some trivial, some tedious, none *elegant*.

**Fun after 30 days?** Only via the daily streak, and only for the narrow segment
that bonds with dailies. No mastery ceiling, no leaderboard, no depth to chase.

**Boring moments:**
- The "fill the remaining empty cells" busywork at the end of every puzzle once the
  milestone order is solved.
- 8×8 boards (`:57` clamps size at 8) become *tedious* not *hard* — more dragging,
  not more thinking.

**Where players quit:**
- Day-1: after 3–4 infinity puzzles that all feel identical, because there's no
  reward, no unlock, no number that matters. `solvedCount` is shown but buys nothing.
- The moment they realize there's no goal — no "win," no ending, no collection, no
  profile. Infinity mode is a treadmill with no carrot.

**Mechanics that create excitement:** the collapse animation
(`puzzle_screen.dart:594`), the milestone pulse-ring telegraph (`:543`), the line
glow. These are all *juice*, not *mechanics* — and under-exploited.

**Mechanics that create frustration:**
- No undo beyond backtracking one cell at a time. Wrong move 20 cells ago = drag
  all the way back.
- The Black-Hole-last rule (`:122`) is logically clean but creates a silent
  "gotcha": players try to enter it early and get blocked with zero feedback.
- Accidental backtrack on jittery fingers (`_onPan`, `:144`).

### Suggestions
- **New mechanic:** make the cosmic ladder *mean something* — see Section 11.
- **New mechanic:** ship the planned wormholes / gravity wells / mass gates / hunter.
- **Better mechanic:** replace random milestone placement + flat walls with a
  **difficulty model** targeting a measured "deduction depth."
- **Remove:** the dead "mop-up" phase.
- **Simplify:** Infinity and Zen are the same screen with a timer toggle (`_isZen`).
- **Combine:** fold Zen into a settings switch; reuse the menu slot for something real.
- **Add:** an **undo button** and **tap-to-truncate** on any path cell.

---

## 2. Retention Analysis

**Day 1:** Weak-to-moderate. Hook is real (pretty, instantly playable) but nothing
tells the player tomorrow exists meaningfully. No notification, no progression teaser.

**Day 7:** Poor without intervention. Only the daily + streak crowd survives. The
streak logic (`daily_service.dart:38`) is correct and is your single best retention
asset — but it's merchandised as a tiny purple line of text.

**Day 30:** Very poor. Nothing accrues. A 30-day player has the identical experience
to a 1-day player.

**Brutal truth:** a *content* problem disguised as a retention problem. Deterministic
puzzles are consumed and discarded.

### Loops to build

**Daily loop**
- One Daily Region **plus** a 3-tier daily: Bronze (solve), Silver (under par time),
  Gold (no backtracks).
- Daily reward: a cosmetic shard / currency feeding collection.
- Streak-protection ("freeze") earned weekly — Duolingo's highest-retention feature.

**Weekly loop**
- A 7-day "Constellation": solve all 7 dailies → unlock a named constellation
  cosmetic + a hard "Anomaly" puzzle. Converts the fragile streak into a collectible set.
- Weekly leaderboard on the daily (friends + global), reset Sunday.

**Monthly loop**
- A "Season" = a themed sector of space. 28 daily puzzles form a star-map; each solve
  lights a star; completing regions reveals art and lore. A finished month = a framed
  star-map on your profile. This is your collection + completionist engine in one.

---

## 3. Player Psychology

**Dopamine (current):** collapse ring + `heavyImpact` haptic on solve (`:166`),
milestone clicks. Adequate, not addictive.

**Surprise moments:** **essentially none.** Deterministic puzzles have no variance —
the core psychological deficit vs. the games cited. Balatro/Suika dopamine comes from
*unexpected* cascades.

**Flow:** the drag-to-trace is inherently flow-friendly. Zen mode is built for it but
does nothing to deepen flow (no ambient audio, no generative visuals).

**Mastery:** thin. Because puzzles are random, there's no *skill expression* a player
can recognize and grow into.

**Collection desire:** **completely unexploited, and malpractice given the theme.** A
literal ladder of beautiful cosmic objects, and the player collects *nothing*.

**Status / completionist:** unserved. No profile, no rank, nothing to 100%.

### Improvements that raise satisfaction / anticipation / "one more"
- **Variable reward on solve** (shard rarity, occasional "supernova" bonus). Keep the
  puzzle deterministic, Skinner-box the *reward* layer.
- **Par + personal-best chase** with satisfying near-miss feedback.
- **Telegraph the next reward** before finishing — anticipation > reward.

---

## 4. Difficulty & Balance

**Early (lvl 1–3, 5×5):** too trivial, too long. Four near-identical baby puzzles
before size even increases (`size = (5 + level ~/ 3)`, `:57`).

**Mid:** the only difficulty lever is grid size + milestone count, both clamped low
(7 milestones, 8×8). Difficulty = bigger board = more dragging, not harder thinking.
A difficulty *valley* masquerading as a curve.

**End:** doesn't exist. After 8×8/7-milestone, every puzzle is the same band forever.

**Spikes:** random — a tangled wall seed sits next to a trivial one. Inconsistent
difficulty breaks trust.

**Repetition:** extreme. One verb (trace), one constraint type.

### Proposals
- **Author difficulty by deduction-depth, not board size.** After generating, run a
  solver that measures how forced each move is; reject puzzles outside the target band.
- **Introduce mechanics as difficulty, not size:** wormholes lvl 5, gravity wells lvl
  10, mass-gates lvl 15. New *rules* create curves; new *cells* create tedium.
- **Onboarding:** a 3-puzzle scripted tutorial; teach the black-hole-last rule explicitly.
- **Pacing:** front-load *variety* (a twist by puzzle 3), not size.

---

## 5. Monetization Review

Zero monetization today (no ads SDK, no IAP). Puzzle audiences are ad-tolerant and
cosmetic-receptive *if you never gate the puzzle itself*.

| # | Opportunity | Mechanism | Sentiment | Rev Impact | Player Accept |
|---|---|---|---|---|---|
| 1 | Rewarded video for streak-freeze / bonus daily | Opt-in watch for a benefit | Positive | **8** | **9** |
| 2 | Cosmetic worldline skins / orb themes | Buy/earn flair | Positive | **6** | **9** |
| 3 | Season Pass (cosmetic-only) | Free + premium cosmetic track | Positive if non-P2W | **9** | **7** |
| 4 | "Remove banner ads" one-time IAP | $2.99 lifetime | Very positive | **6** | **9** |
| 5 | Hint / solver token | Watch ad / spend currency for next move | Risky | **7** | **5** |
| 6 | Menu-only banner | Static banner on home screen | Neutral | **5** | **7** |
| 7 | Season/Sector expansions | New mechanic packs as themed seasons | Positive | **6** | **8** |

**Rules you must not break:** never put a timer/ad between the player and *retrying*;
never gate the Daily; daily hints must be leaderboard-neutral. Fastest safe money:
**#1 + #2 + #4**. Hold #3 until the collection/star-map exists to fill it.

---

## 6. Visual & Art Direction

**Strength.** Dark cosmic palette, glowing gold worldline (`:517` blur + core stroke),
pulsing milestone rings, squashed accretion-disk black hole (`:548`). The most
finished-feeling part of the game.

**Problems:**
- **Monospace everything** reads "programmer prototype," caps perceived value and
  screenshot appeal.
- **Static board** — flat `#070b12`, no starfield, no parallax, no nebula. The canvas
  begs for ambient life.
- **The collapse is underwhelming** — a single ring + flash for the *titular event*.
  This is your trailer money-shot and it's an afterthought.
- **Milestones are flat circles**, no object identity, despite collection ambitions.

### To create "wow" / screenshots / trailers / social
- Animate the collapse into a real **implosion + shockwave + galaxy zoom-out reveal**
  ("this region was one star in a galaxy"). That zoom-out is the hook shot.
- Living starfield background with parallax tied to the drag.
- Comet-trail / particle wake on the worldline; milestones visibly *accrete* when consumed.
- One signature display font for branding.

---

## 7. Audio Design

**Current state: none.** Only haptics. For a game whose retention depends on *feel*,
shipping silent leaves the single highest-ROI polish on the table.

### Recommendations
- **Signature sound:** rising harmonic tone *per milestone*, pitched up the ladder —
  Particle low, Black Hole a resolving chord.
- **Accretion ASMR:** soft granular "absorption" texture intensifying with path length.
- **Reward sound:** deep bass-swell + reverse-cymbal on collapse — the dopamine stinger.
- **Viral/ASMR angle:** Zen mode where the **path plays an instrument** (each cell = a
  note) → "weirdly relaxing" TikToks. Genuinely novel and shareable.
- **Music:** generative ambient drone for Zen; subtle rhythmic pulse for timed modes.
- Keep it procedural (no asset bloat) — matches the stated constraint.

---

## 8. Marketability

| Game | Why someone plays *that* | Can you beat it? |
|---|---|---|
| 2048 | Dead-simple emergent merging, infinite | No — not a merge game (yet) |
| Tetris | Perfect skill-mastery loop | No |
| Suika | Physics + accretion + push-luck, *streamable* | **Only if you build real accretion (Sec 11)** |
| Fruit Merge | Casual merge dopamine | No, different genre |
| Balatro | Roguelike build variance, "one more run" | No — wrong genre |
| Luck Be a Landlord | Synergy discovery | No |
| **(Real peer) Zip / Flow / Sudoku** | Daily calm logic, streaks | **Yes — this is your actual ring** |

**Why play this instead?** Right now: *because it's prettier than Zip.* Not enough.

**Unique?** Cosmic theme (unexploited) + black-hole-must-be-last twist (one rule). Thin.

**Memorable?** Nothing yet bites. The collapse *should* be the hook and isn't strong enough.

**Viral potential:**
1. The **galaxy zoom-out reveal** — a screenshot people share.
2. **Path-as-instrument Zen audio** — TikTok ASMR.
3. A novel **accretion mechanic** (Sec 11) producing *emergent cascades worth filming*.

Emoji share card (`_buildShareText`, `:170`) is a good instinct, but emoji-grid
sharing only goes viral when the puzzle is a *shared global event* (Wordle). Lean hard
into the Daily being **the** thing.

---

## 9. Hit Potential Assessment

Scored as the game **exists today**.

| Axis | Score | Why |
|---|---|---|
| Fun | **5/10** | Pleasant, tactile, but shallow and repetitive; no surprise, no stakes. |
| Originality | **3/10** | Mechanically a Zip clone; originality is skin-deep. |
| Accessibility | **9/10** | Excellent — instant, one-finger, portrait. Real strength. |
| Retention | **3/10** | Streak + daily is the only hook; nothing accrues. |
| Monetization | **2/10** | None implemented; low puzzle ARPU without ads infra. |
| Virality | **3/10** | Share card exists but nothing compels sharing. |
| Visual Appeal | **7/10** | Cohesive, pretty — held back by monospace + static board + weak collapse. |
| Marketability | **4/10** | "Prettier Zip" is a hard pitch; no headline hook. |

**Composite ~4.5/10 as-is.** A competent, attractive prototype of a derivative puzzle.
Not yet a product.

---

## 10. Ruthless Critique — The $5M Publisher Verdict

*I'm the publisher. I've seen 400 puzzle pitches this year. Here's why I'm hesitating.*

**What stops me funding it:**
1. It's a reskin of a free puzzle (Zip), and before that a textbook Hamiltonian-path
   puzzle. "But ours is cosmic" doesn't defend a $5M check.
2. **No retention spine.** Procedural deterministic puzzles are consumed and forgotten.
   Show me why anyone opens this on day 14.
3. **No proven monetization** in a low-ARPDAU genre unless you manufacture the Wordle
   water-cooler effect — and that's *my* marketing risk, not yours.

**Concerns:** the theme/mechanic mismatch says the team hasn't decided what game this *is*.

**Risky:** procedural gen with no authored difficulty = inconsistent quality at scale =
"boring/repetitive" review-bombing.

**Weak:** no audio, no collection, no progression, no endgame; two of three modes are
the same screen.

**Derivative:** the core loop, the emoji share card (Wordle), the streak
(Duolingo/Wordle). Known parts, no new one.

### Exactly how to fix it (to get the check)
1. **Pick one defensible, novel, *filmable* mechanic and build the game around it**
   (Section 11). No new mechanic = no funding.
2. Build the **collection / star-map meta** for a 30-day reason to exist.
3. Add **audio + a spectacular collapse**. Non-negotiable for feel.
4. Replace random gen with **difficulty-authored gen**.
5. Prove **D7 > 20%** in soft-launch before scaling spend.

---

## 11. Transform It Into a Hit — and the Defining Mechanic

> **The single most powerful mechanic that creates Balatro/Vampire-Survivors/Suika
> "one more run" addiction.**

**Why those three are addictive — shared DNA:**

> **Emergent, partly-unpredictable cascades that the player sets up but cannot fully
> control, with escalating stakes and a risk/reward gamble on every action.**

Suika: you place a fruit, physics decides the cascade. Balatro: you build a hand, the
multipliers cascade beyond what you can compute. Vampire Survivors: you pick upgrades,
the screen erupts. **Determinism is the enemy of "one more run."** This game is
currently 100% deterministic. That's the whole problem.

The defining mechanic must inject **controlled emergence** into the trace puzzle
without throwing away its tactile path-drawing core:

### ⭐ The Defining Mechanic: ACCRETION CASCADE

**Pitch:** *You don't just trace a path — you trace a path that triggers a
gravitational chain reaction, and the longer/riskier your line, the bigger the
collapse you set off.*

**How it works:**
1. **Every cell holds cosmic mass** (particles, dust) — not just milestone checkpoints.
2. Dragging the worldline **accumulates the mass** of every cell into a "singularity
   gauge." The line **grows visibly heavier and brighter** — finally making the cosmic
   ladder *mean something*.
3. **Chain rule:** passing through *same-tier* cells consecutively builds a **multiplier
   chain** (the Balatro layer). Passing a higher tier **banks** the chain and bumps your
   tier — *but resets the chain*. Constant **push-your-luck tension**: keep chaining for
   multiplier, or cash out to the next tier?
4. **The collapse is now emergent and scored.** Hitting the Black Hole triggers an
   **accretion cascade**: accumulated mass × chain multiplier pulls in surrounding cells
   in a physics ripple, and **chain-reactions fire** — nearby same-tier objects detonate
   together, pulling more mass, triggering more detonations. **You set it up; physics
   finishes it; you watch a number explode you couldn't fully predict.** Suika cascade +
   collapse animation, fused.
5. **Risk:** greedier chains mean a longer, more exposed path — and **decay / dark-matter
   tiles** punish dawdling. Greed vs. safety on every run.
6. **The score is the run.** Infinity becomes a **high-score push-your-luck run**: "I
   almost hit 10M mass, ONE more run." The daily becomes "beat today's global cascade."

**Why it becomes the defining feature:**
- **Resolves the theme/mechanic war** — mass, accretion, chains, collapse: the fantasy
  finally matches the verb.
- **Injects the missing emergence** — set up by skill, resolved by chain-reaction
  surprise. The exact Suika/Balatro formula in a line-drawer.
- **Creates "one more run"** — replaces binary "did I solve it" with unbounded "how big
  did I make it." Unbounded scores + near-misses + a gamble = compulsion.
- **It's filmable** — a snowballing cascade into a galaxy zoom-out is a Reels machine.
- **Preserves your strengths** — tactile drag, gorgeous line, instant accessibility.
- **Feeds every other system** — mass → currency → collection → season pass → leaderboards.

**Keep a "Classic/Daily" pure-logic mode** for the Sudoku crowd. But make **Accretion**
the headline, the trailer, the store hero. *That's* the game capable of 10M+ downloads.

### Aggressive scaling targets
- **→ 1M:** Accretion mode + audio + spectacular collapse + collection/star-map +
  daily-cascade leaderboard. Soft-launch, D7 > 25%.
- **→ 10M:** Nail the *filmable cascade*, seed creators, lean the brand on the galaxy
  zoom-out and ASMR Zen audio. Season cosmetics. Share loop = cascade *replay*, not emoji.
- **→ 100M:** Cascade must define a micro-genre ("cosmic Suika-meets-Zip"), cross-platform
  daily as a global event, live-ops seasons. A 2–3 year live game. The mechanic above is
  the only thing here with that ceiling.

---

## 12. Deliverables

### Top 10 Improvements
1. Build the **Accretion Cascade** mechanic — the defining feature.
2. Add **procedural audio** (milestone tones, collapse stinger, Zen path-instrument).
3. Make the collapse a **spectacular implosion + galaxy zoom-out reveal**.
4. Build a **collection / star-map meta-progression**.
5. **Difficulty-authored generation** (deduction-depth targeting).
6. **Undo button + tap-to-truncate** path.
7. Ship **wormholes / gravity wells / mass gates** as the real difficulty curve.
8. **Living starfield** + comet-trail worldline + accreting milestones.
9. **Explicit onboarding** (teach black-hole-last; never silently reject).
10. **Merge Zen into a setting**; free the menu slot for Campaign/Collection.

### Top 10 Risks
1. Theme/mechanic mismatch (existential).
2. Derivative core loop (Zip clone) — no defensibility.
3. No retention spine beyond a fragile streak.
4. Procedural quality inconsistency → "repetitive" reviews.
5. No audio = flat feel.
6. No monetization model proven; low puzzle ARPU.
7. Endgame void.
8. Silent rule-rejection frustration.
9. Difficulty = board size = tedium.
10. Big-board mop-up busywork.

### Top 10 Monetization Opportunities
1. Rewarded video: streak-freeze / bonus region (8/9).
2. Cosmetic worldline & orb skins (6/9).
3. Cosmetic-only Season Pass (9/7).
4. "Remove ads" lifetime IAP (6/9).
5. Hint/solver tokens, leaderboard-excluded (7/5).
6. Menu-only banner (5/7).
7. Themed Sector/season expansions (6/8).
8. Profile/star-map cosmetic frames (5/8).
9. Cascade-replay "supernova" VFX packs (6/8).
10. Sponsored daily regions, later (6/6).

### Top 10 Retention Features
1. Tiered daily (Bronze/Silver/Gold).
2. Streak-freeze token.
3. Weekly Constellation set.
4. Monthly Season star-map.
5. Collection of cosmic objects/skins.
6. Daily cascade leaderboard.
7. Personal-best + par chase with near-miss feedback.
8. Push notification (daily + streak-at-risk).
9. Unbounded high-score run (Accretion Infinity).
10. Profile/identity (rank, badges, framed star-maps).

### Top 10 Viral Features
1. Galaxy zoom-out reveal on collapse.
2. Filmable accretion cascade.
3. Zen path-as-instrument ASMR audio.
4. Cascade *replay* share.
5. Global daily as water-cooler event.
6. Friend leaderboard challenge links.
7. "Beat my cascade" shareable seed.
8. Signature collapse sound.
9. Rare "supernova" cosmetic flexes.
10. Star-map completion shareable image.

### Top 10 UX Improvements
1. Undo button.
2. Tap-any-path-cell to truncate.
3. Explain *why* a move is blocked (black-hole-last).
4. Reduce accidental-backtrack sensitivity (`_onPan`, `:144`).
5. Scripted 3-step tutorial.
6. Bigger, celebratory streak presentation.
7. Real display font for branding.
8. Next-reward telegraph before solve.
9. Haptic + audio confirmation parity on every action.
10. Settings screen (audio, haptics, hide-timer) — currently none exists.

### Final Revised Game Design
*Singularity: Collapse* becomes a **cosmic accretion roguelite-puzzle**. You trace one
worldline through a star-region, consuming mass and building same-tier multiplier chains
under push-your-luck tension (chain higher vs. cash out, greed vs. spreading decay).
Finishing on the Black Hole triggers an **emergent accretion cascade** — a chain-reaction
physics collapse scored on mass × multiplier — then zooms out to reveal your region was
one star in a galaxy you're slowly mapping. **Three pillars:** *Daily* (one global region,
tiered goals, leaderboard, streak/collection), *Cascade* (endless high-score push-your-luck
run — the "one more run" engine and headline mode), and *Classic* (pure-logic trace puzzles
for the Sudoku crowd). Meta-progression is a season star-map of collectible cosmic objects
and worldline skins. Audio is fully procedural. Monetization is strictly cosmetic + optional
rewarded video, never gating a puzzle.

### Publisher Investment Verdict
**As-is: PASS.** A polished prototype of a derivative puzzle — no defensible mechanic, no
retention spine, unproven monetization. **Conditional fund** *if and only if* the team
commits to (1) the Accretion Cascade as a genuine, filmable, novel mechanic, (2) a
collection/season meta, and (3) a soft-launch demonstrating **D7 > 20%**.

### Estimated Market Potential
- **As-is:** 50k–250k lifetime downloads, near-zero revenue. A portfolio piece.
- **+ audio + collapse + collection + daily polish (no new core mechanic):** 250k–1M
  downloads, modest cosmetic/ad revenue — a respectable Zip-tier daily puzzler.
- **+ Accretion Cascade + full meta + live-ops:** genuine 5M–50M ceiling *if* the cascade
  lands as filmable and the daily becomes a global event. The mechanic is the only thing
  here with a top-tier ceiling; everything else is execution.

### Prioritized Development Roadmap
- **Phase 0 — Feel (1–2 wks, highest ROI):** Procedural audio + spectacular collapse +
  galaxy zoom-out + undo/truncate + fix backtrack sensitivity + teach black-hole-last.
- **Phase 1 — The Mechanic (3–5 wks):** Prototype **Accretion Cascade**. Playtest for
  "one more run." **Gate everything else on this proving fun.**
- **Phase 2 — Meta (2–3 wks):** Collection + season star-map + cascade leaderboard +
  tiered daily + streak-freeze. Merge Zen into settings.
- **Phase 3 — Difficulty (1–2 wks):** Difficulty-authored generation; ship wormholes /
  gravity-wells / mass-gates as the curve.
- **Phase 4 — Monetize (1–2 wks):** Rewarded video (#1), cosmetic skins (#2), remove-ads
  IAP (#4). Hold the season pass until the collection is rich.
- **Phase 5 — Soft-launch & measure:** D1/D7/D30 + ARPDAU in a small market. Scale spend
  only on D7 > 20%.

---

**Bottom line:** You've built a genuinely *attractive, accessible* puzzle — most
prototypes fail at exactly that. But it's a beautiful clone of a free game, and beauty
isn't a moat. The cosmic theme you chose is quietly screaming at you to build accretion.
Build it. The Accretion Cascade is the one idea here that turns "a prettier Zip" into a
game worth $5M and a shot at the charts. Everything else is polish on a body that still
needs a heart.
