# Testing on iOS via Codemagic + TestFlight (no Mac)

Step-by-step to get **Singularity: Collapse** onto your iPhone for testing, building
& signing entirely in the cloud (you're on Windows, no Mac needed). The repo already
contains the build config (`codemagic.yaml`) and the export-compliance plist key.

Bundle ID (already set, never changes): **`com.sympathyforthedevil.singularityCollapse`**

> ✅ **LIVE as of 2026-06-12** — the first signed build built, uploaded, and installed
> via TestFlight (Apple ID `6779779848`, API key `CodemagicAppStore` / App Manager role).
> Builds are **manual** (start from the Codemagic UI). The one non-obvious gotcha was
> code signing on a brand-new app — see the **Signing** note under step 8.

Legend: ☐ to do · ✅ done

---

## Phase 1 — Apple side (App Store Connect) · ~20 min, one time

☐ **1. Create the app record.**
- Sign in at **appstoreconnect.apple.com** → **Apps → ➕ → New App**.
- Platform **iOS**; Name e.g. **Singularity: Collapse**; Primary language English;
  **Bundle ID** = select `com.sympathyforthedevil.singularityCollapse` from the
  dropdown. (If it isn't listed: developer.apple.com → Certificates, IDs & Profiles
  → Identifiers → ➕ → App ID with that bundle id, then come back.)
- **SKU** = any unique string, e.g. `singularity-collapse-001`. User access: Full.
- Create. Then open **App Information** and note the numeric **"Apple ID"**
  (e.g. `6480000000`) — you'll paste this into `codemagic.yaml`.

☐ **2. Accept agreements.** Business → **Agreements**: accept the free-apps
agreement (banking/tax not needed for TestFlight; only for paid/IAP later).

☐ **3. Generate an App Store Connect API key** (this is what lets Codemagic upload
without a Mac password):
- **Users and Access → Integrations** tab → **App Store Connect API** → ➕.
- Name it `codemagic-ci`. **Access role = App Manager** (NOT Admin — least privilege:
  it can upload builds + manage TestFlight, but can't touch banking, users, or delete
  the app).
- **Generate**, then **Download the `.p8` file** — you can only download it ONCE.
- Copy the **Key ID** (next to the key) and the **Issuer ID** (top of the Keys page).
- 🔒 Save the `.p8` + Key ID + Issuer ID in your password manager. Never commit the
  `.p8` to git.

---

## Phase 2 — Codemagic setup · ~15 min, one time

☐ **4. Sign up** at **codemagic.io** with your **GitHub** account.

☐ **5. Connect the repo (scoped).** When installing the **Codemagic GitHub App**,
choose **"Only select repositories" → `singularity_collapse`** (not "All
repositories"). You can revoke this anytime at GitHub → Settings → Applications.

☐ **6. Add the app** in the Codemagic dashboard. It will detect `codemagic.yaml`.

☐ **7. Add the API key to Codemagic.** Team settings (gear) → **Integrations** →
**App Store Connect** → **Add key**:
- Upload the **`.p8`**, paste the **Issuer ID** + **Key ID**.
- **Name the key `CodemagicAppStore`** ← this must match `integrations.app_store_connect`
  in `codemagic.yaml` (or change the yaml to match your chosen name).

☐ **8. Fill the two placeholders in `codemagic.yaml`** (then commit/push, or I can):
- `integrations.app_store_connect:` → your key name from step 7 (`CodemagicAppStore`).
- `APP_STORE_APPLE_ID:` → the numeric Apple ID from step 1.

> **Signing — the one non-obvious step (do this before the first build).** The
> implicit `ios_signing` block does *not* work for a brand-new app: it only *fetches*
> existing signing files, and `--create` cannot mint the first distribution
> certificate without a private key to base it on (you'll hit "No matching profiles
> found" / "Cannot save Signing Certificates without certificate private key"). The
> fix, already in `codemagic.yaml`:
> 1. Generate an RSA key once: `openssl genrsa -out cert_key.pem 2048` (backup kept at
>    `~/collapse-signing/codemagic_cert_key.pem`).
> 2. In Codemagic → your app → **Environment variables**, add it as a **Secure** var
>    named **`CERTIFICATE_PRIVATE_KEY`** in the group **`appstore_credentials`** (paste
>    the whole `-----BEGIN/END PRIVATE KEY-----` block).
>
> The workflow's `fetch-signing-files --type IOS_APP_STORE --create
> --certificate-key=@env:CERTIFICATE_PRIVATE_KEY` then mints the certificate + App
> Store profile from that key on the first build and **reuses the same cert on every
> later build** (no certificate churn, no Apple cert-cap problems). The API key role
> must be **App Manager** (sufficient — it can create certs/profiles).

---

## Phase 3 — Build & install · ~15 min first time, ~1 tap after

☐ **9. Run a build.** Codemagic → your app → **Start new build** → pick the
**`iOS · TestFlight`** workflow → Start. (~10–15 min: it builds, signs, uploads.)

☐ **10. Wait for processing.** App Store Connect → your app → **TestFlight** shows the
build "Processing" for ~5–15 min. (Export compliance won't prompt — the plist key
`ITSAppUsesNonExemptEncryption = NO` is already set.)

☐ **11. Add yourself as an internal tester.** TestFlight → **Internal Testing** → ➕
group → add your Apple ID (already a user on the account). **Internal builds are
available immediately — no Beta App Review.**

> **Turn on "Enable Automatic Distribution" for the internal group.** Then every
> uploaded build auto-distributes to you once Apple finishes processing — no manual
> per-build step. This also makes Codemagic's `submit_to_testflight` post-processing
> step irrelevant: that step is *racy* (it can fire before Apple finishes processing
> and go red), but the build still uploads fine and automatic distribution picks it up.

☐ **12. Install on your iPhone.** App Store → install **TestFlight** → sign in with
your Apple ID → the build appears → **Install** → play. 🎉

**To ship an update later:** push your code, then Start new build in Codemagic →
new build to TestFlight → tap Update in TestFlight on your phone. (Or uncomment the
`triggering:` block in `codemagic.yaml` to auto-build on every push to `main` — note
that spends free build minutes faster.)

---

## Notes / safety / future

- **Free tier:** Codemagic's free macOS build minutes are plenty for solo testing;
  verify the current allotment at codemagic.io/pricing. Builds are **manual by
  default** here to conserve them.
- **Kill switches:** revoke the API key in App Store Connect, and/or uninstall the
  Codemagic GitHub App — either instantly cuts Codemagic's access. Your source,
  Apple account, and certs remain yours.
- **No lock-in:** if you later get a Mac, open the project in Xcode, select your Team,
  and build/upload directly — nothing here is Codemagic-specific except this one
  `codemagic.yaml` file.
- **App display name** on the device is "Singularity Collapse" (`CFBundleDisplayName`
  in `ios/Runner/Info.plist`); the store-listing title can be "Singularity: Collapse".
