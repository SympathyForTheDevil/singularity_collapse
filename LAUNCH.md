# Launch Plan — Singularity: Collapse

The path from "feature-complete v1" to "live on Google Play + Apple App Store."
Descent Phase B is **deferred to a post-launch feature update** (see `ROADMAP.md`);
the pre-launch focus is **polish · monetization · progression menu**, then ship.

Legend: ☐ todo · ◐ in progress · ✅ done

---

## 0. Status & the one irreversible thing (already handled)

- ✅ **Application IDs are final and real** (you can NEVER change these after first
  publish): Android `com.sympathyforthedevil.singularity_collapse`, iOS
  `com.sympathyforthedevil.singularityCollapse`. Good to go.
- ✅ Android **release keystore** exists + backed up (`android/collapse-release.jks`,
  GitHub secrets set). **Losing it blocks all future Play updates — keep the backup.**
- ✅ CI builds a **signed APK** + an **unsigned IPA** (`.github/workflows/build.yml`).
- Current version: `1.0.0+1` (pubspec). Bump per release.

---

## Part 1 — Remaining development (gates the store builds)

### A. Pre-release polish
- ✅ **Store name = "Singularity: Collapse"** (confirmed clear on both stores;
  `singularitycollapse.com` registered). In-app wordmark stays "SINGULARITY". Code
  display names aligned — `MaterialApp.title` = "Singularity: Collapse"; `android:label`
  + iOS `CFBundleDisplayName` = "Singularity Collapse". Set the **listing title** in the
  Play/App Store consoles at submission. (App **IDs** unchanged.)
- ✅ **About/credits** in Settings — version · developer (Adam Ettinger) · website /
  support / privacy links · **open-source licenses** (`showLicensePage` — satisfies the
  OSS notice obligation). ⚠ support email is a placeholder (`support@singularitycollapse.com`).
- ✅ **iOS TestFlight pipeline LIVE** (2026-06-12) — first signed build built, uploaded,
  and installed via TestFlight (Apple ID `6779779848`, API key `CodemagicAppStore`).
  Builds are **manual** from the Codemagic UI. Signing uses a persistent RSA key in the
  secure env var `CERTIFICATE_PRIVATE_KEY` (group `appstore_credentials`) — see
  `IOS_TESTFLIGHT.md` step 8. Recommend enabling **Automatic Distribution** on the
  internal tester group so future builds appear without the racy post-processing step.
- ☐ **Gate / remove the `· dev ·` menu** before any public/production build (keep it
  for internal/testing tracks behind a flag, or strip it for production).
- ◐ **Readability pass** — home done; finish Settings / Streak / Field Guide / in-game
  HUD / overlays from your screenshots.
- ☐ **On-device tuning confirmation** — entropy feel (just retuned), multiverse
  length, entangled frequency.
- ☐ **Switch the release artifact to AAB** for Play: `flutter build appbundle
  --release` (Play requires an Android App Bundle; keep the APK for sideload testing).
  Add an AAB step to CI.
- ☐ **Decide iOS device family: iPhone-only vs Universal.** It's a portrait phone
  game → **iPhone-only** is simplest (skips iPad screenshots + iPad QA). Set in Xcode.
- ☐ **Crash reporting / analytics decision** (affects the privacy disclosures below).
  Recommend launching *without* (the app stores only local prefs → minimal data) and
  adding Crashlytics/Sentry in a later update if wanted.

### B. Monetization (Phase 3) — model chosen: **Free + rewarded ads + IAP**
- ☐ **`PremiumService`** — persisted entitlement flag (dev toggle now; store purchase
  later). Restore-purchases support. Premium = removes ads + unlocks Syntropy full
  picker / Penrose theme / unlimited hints.
- ☐ **Rewarded ads** via **`google_mobile_ads`** (AdMob): e.g. watch an ad to earn a
  hint or an extra daily replay. Free tier stays fully playable without ever watching.
- ☐ **`in_app_purchase` plumbing** — a "Premium / Remove Ads" product across both
  stores; buy + restore; sandbox/license testing.
- ☐ **Store-side setup** — IAP product in App Store Connect + Play Console; accept
  **Paid Apps agreement** + **tax/banking**; create an **AdMob account**, register the
  app, get ad-unit IDs, link AdMob ↔ Play/App Store Connect.
- ⚠ **Ads change the privacy story** (vs an IAP-only build): the ads SDK collects
  device/advertising identifiers. This requires: an updated **privacy policy**, fuller
  **Google Data safety** + **Apple privacy** disclosures, the iOS **App Tracking
  Transparency** prompt (`NSUserTrackingUsageDescription` + ATT flow) if ads
  personalize, and the **Google UMP / consent** flow for GDPR regions. Budget for this.

### C. Progression menu (Phase 4) — ✅ done
- ✅ "✦ NEW MECHANIC UNLOCKED ✦" celebration card on first encounter of a mechanic.
- ✅ **Achievements screen** (🏆 on Home) — ~14 achievements with progress bars +
  the mechanics-discovered progression (moved *off* the cluttered home menu into this
  submenu). `StatsService` tracks lifetime counters (`_onSolved`).
- ☐ Optional later: an achievement-unlocked toast the moment one is earned.

---

## Part 2 — Accounts & licensing (do these FIRST — they have lead times)

| Item | Cost | Lead time | Notes |
|---|---|---|---|
| **Apple Developer Program** | **$99 / year** | 24–48h (longer w/ ID check) | Individual (your legal name as seller) is fastest. **Organization** needs a free **D-U-N-S number** (days–weeks to obtain) — only if you want a company name. |
| **Google Play Developer** | **$25 one-time** | hours–days (+ ID verification) | New **personal** accounts must complete a **closed test: ≥12 testers, 14 days** before production access (verify the current number in Console — Google has changed it). Organizations are exempt but need org verification. |
| **Tax & banking (for IAP)** | $0 | — | App Store Connect → Agreements/Tax/Banking; Play Console → Payments profile. Must be complete before selling. |

> ⏱ **The Google 14-day closed test and Apple/Google ID verification are the long
> poles. Register both developer accounts NOW**, in parallel with the dev work above.

---

## Part 3 — Website (privacy policy + support — both stores require it)

✅ **LIVE at https://singularitycollapse.com** (2026-06-13) — static site, hosted free on
**GitHub Pages** (repo `SympathyForTheDevil/singularitycollapse-site`), custom domain via
Namecheap DNS (4 A records → GitHub IPs + `www` CNAME), valid auto-provisioned HTTPS cert,
`www`→apex redirect. Pages match the in-app About links exactly.
- ✅ **Privacy policy** — `https://singularitycollapse.com/privacy`. Written to match v1
  reality (local storage only; no accounts/servers/analytics/ads; purchases via
  Apple/Google). ⚠ **Update it if ads/analytics are ever added.**
- ✅ **Support page** — `https://singularitycollapse.com/support` (+ FAQ). Satisfies
  Apple's support-URL and Google's support-email requirements.
- ✅ **Landing page** — hero + features + collapse ladder (asset-free CSS/SVG black hole).
- ◐ **Support email** — `support@singularitycollapse.com` → set up **Namecheap free email
  forwarding** to adam.ettinger@gmail.com (do/confirm the forwarder).
- ◐ **Enforce HTTPS** — tick the box in GitHub Pages once the (lagging) DNS check flips
  green; the cert is already active.

---

## Part 4 — Google Play, step by step

1. ☐ Create the app in **Play Console** (default language, app/game, free, paid-IAP).
2. ☐ **Build a signed AAB** and enroll in **Play App Signing** (Google holds the app
   signing key; your existing keystore is the *upload* key).
3. ☐ **Store listing**: title (≤30 chars), short description (≤80), full description
   (≤4000); **app icon 512×512**, **feature graphic 1024×500**, **2–8 phone
   screenshots** (portrait, from a device/emulator), optional 30s trailer.
4. ☐ **Content rating** (IARC questionnaire → likely *Everyone*), **Data safety** form
   (declare: local storage only + IAP; no data shared), **Target audience** (13+,
   *not* primarily children → avoids Families policy), **Ads** = none, **App access**
   (all features available without login).
5. ☐ Upload AAB to **Internal testing** (instant, ≤100 testers) → smoke test.
6. ☐ **Closed testing**: recruit **≥12 testers**, keep them opted-in **14 days**
   (this is the gate to production for new personal accounts). Use the **Pre-launch
   report** (free automated device testing) to catch crashes.
7. ☐ Apply for **production access**, then **roll out** (staged % rollout recommended).

---

## Part 5 — Apple App Store, step by step

### The Mac question (you asked) — recommendation
You do **not** need to buy a Mac. In order of cost:
1. **GitHub Actions macOS runners (recommended).** CI already builds the IPA — add
   **signing + fastlane** to build → sign → upload to **TestFlight/App Store** entirely
   in CI. ~$0 for a public repo (free minutes otherwise). No Mac to rent.
2. **MacinCloud pay-as-you-go (~$1/hr)** — best for the *one-time bootstrap* (create
   certs, the App Store Connect app record, first manual upload, any Xcode tweaks).
3. **AWS EC2 Mac** — powerful but 24h-minimum dedicated host (~$25+/day); overkill.
4. **Buy a used M-series Mac mini (~$400–600)** — worth it only if you'll maintain the
   app long-term and want the smoothest Xcode/dev experience.

> **Suggested path:** a few hours on **MacinCloud** (or a borrowed Mac) to create the
> certificates + App Store Connect app + first TestFlight upload, then **automate all
> future builds via GitHub Actions CI** (fastlane `match` for certs, `pilot`/`deliver`
> for upload). After bootstrap you rarely touch a Mac.

### Steps
1. ☐ Register the **App ID** (bundle id already set) + enable the **In-App Purchase**
   capability.
2. ☐ Create **Apple Distribution certificate** + **App Store provisioning profile**
   (manual via Xcode/App Store Connect, or `fastlane match` storing them in a private
   git repo — best for CI).
3. ☐ Create the app in **App Store Connect**.
4. ☐ Set **`ITSAppUsesNonExemptEncryption = NO`** in `Info.plist` (standard for a game
   with no custom crypto — skips the export-compliance prompt on every upload).
5. ☐ **Screenshots**: at least the **iPhone 6.9"** set (1320×2868) — App Store Connect
   can reuse it for smaller sizes; add 6.5" if asked. (No iPad set if iPhone-only.)
6. ☐ **App Privacy nutrition label** (declare data types — likely "Data Not Collected"
   + Purchases), **age rating** questionnaire, **privacy policy URL**, **support URL**.
7. ☐ Upload the signed build → **TestFlight** (internal testers get it instantly;
   external testers need a quick review). Smoke test, esp. **sandbox IAP purchase +
   restore**.
8. ☐ Attach the build, set **pricing** (free + IAP), fill metadata, **submit for
   review** (typically 24–48h; add reviewer notes if anything needs explaining).

---

## Part 6 — Suggested critical path

```
Week 0 (now): register Apple + Google dev accounts (start ID verification) ┐
              · finish polish (name, dev-menu, readability, AAB)            │ parallel
              · build monetization (PremiumService + IAP) + progression     │
Week 1:       internal testing both stores; create store listings,         │
              privacy/support site; set up IAP products + tax/banking      ┘
Week 1–3:     Google CLOSED TEST running (≥12 testers, 14 days) ← long pole
              Apple TestFlight beta in parallel
Week 3–4:     Google production application + review; Apple submit + review
Launch:       staged rollout on Play; release on App Store
```
Realistic: **~3–5 weeks** from "accounts created" to "live on both," dominated by the
Google 14-day closed test + review buffers (assuming dev work lands in parallel).

---

## Part 7 — Also consider (gotchas & polish)

- **Restore Purchases is mandatory** (both stores) for non-consumable IAP; no external
  payment links in-app (must use store billing).
- **Increment the build number every upload** (Android `versionCode` — CI uses
  `github.run_number` ✅; iOS `CFBundleVersion` — wire into CI too).
- **Min OS versions**: confirm iOS deployment target + Android `minSdk` are sane
  (Flutter defaults are fine; note them in the listing's device support).
- **App size** ~53 MB — comfortably under all store limits.
- **Demo/review access**: provide reviewers a note on reaching premium features for
  testing (no demo account needed — it's offline).
- **Pre-launch legal**: the synthesized classical music is public-domain compositions
  rendered by us (no recording license needed) — fine to ship; keep it that way.
- **Post-launch**: respond to reviews, watch crash/ANR vitals, plan the **Descent**
  feature update, basic ASO (keywords, screenshots, a short trailer).
- **Accessibility**: the readability pass helps; consider larger-text support later.

---

## Quick cost summary (year one)

| | Cost |
|---|---|
| Apple Developer Program | $99 / year |
| Google Play Developer | $25 one-time |
| Website (GitHub Pages) | $0 (or ~$12/yr custom domain) |
| Cloud Mac (bootstrap only, optional) | ~$0–30 (CI is free; MacinCloud hourly) |
| **Minimum to launch both stores** | **~$124 first year** |
