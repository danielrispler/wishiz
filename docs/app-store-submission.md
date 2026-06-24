# Wishiz — App Store Connect Submission Cheat-Sheet

Copy-paste values to clear the metadata blocks. Pages are served by the Go API as
base routes (`/privacy`, `/support`), reachable in every `SERVICE_ROLE`.

---

## 1. URLs (App Store Connect → App Information + Version)

| Field | Value |
|-------|-------|
| **Support URL** | `https://wishiz-api-pdst26qeja-ey.a.run.app/support` |
| **Privacy Policy URL** | `https://wishiz-api-pdst26qeja-ey.a.run.app/privacy` |
| **Marketing URL** (optional) | leave blank |

> **Use the `run.app` host above — it is the canonical host.** `wishiz.app` was
> never DNS-mapped to Cloud Run, so the app, share links and deep links all run
> against the `wishiz-api` `run.app` host directly.
>
> **Before you submit:** deploy, then `curl -I` both URLs and confirm `200`.
> Apple fetches them live during review — a 404 = rejection.

---

## 2. Name, Subtitle, Promo

| Field | Value |
|-------|-------|
| **App Name** | `Wishiz` |
| **Subtitle** (≤30 chars) | `Your editorial wishlist` |
| **Promotional Text** (≤170) | `Paste any product link and Wishiz pulls in the name, price, and image — turning scattered tabs into one beautiful, shareable wishlist.` |

---

## 3. Description (paste as-is)

```
Wishiz is the beautifully simple way to save everything you want — in one curated place.

Paste any product link and Wishiz instantly pulls in the name, price, and image, turning a messy collection of browser tabs and screenshots into a clean, editorial wishlist you'll actually enjoy revisiting.

WHY YOU'LL LOVE IT
• Save from anywhere — drop in a link from any store and we do the rest
• Organize your way — build wishlists for birthdays, holidays, your home, or that one big splurge
• Share with the people who matter — invite family and friends to view or add to a list, so gifting is never a guessing game
• Always up to date — prices and details synced across your devices
• Thoughtfully designed — a calm, premium interface with no ads and no clutter

Whether you're planning a birthday, building a gift registry, or just keeping track of the things you love, Wishiz keeps it all organized and gorgeous.

Start your first wishlist in seconds. It's free to get started.
```

---

## 4. Keywords (paste as-is — 98/100 chars, no spaces)

```
wishlist,gift,gifts,registry,shopping,wishlists,birthday,christmas,present,giftideas,wantlist,save
```

---

## 5. Copyright

```
2026 Daniel Rispler
```

---

## 6. Category

| Field | Value |
|-------|-------|
| **Primary** | Shopping |
| **Secondary** | Lifestyle |

---

## 7. Content Rights (App Information → Content Rights)

**Select: "Yes, it contains, shows, or accesses third-party content"** and tick
the confirmation that you have the rights / are authorized to use it.

**Why** (don't blindly pick "No"): Wishiz fetches and displays product names,
prices, and **images from third-party retailer pages** that the user imports.
That is third-party content. It is user-supplied (the user pastes public product
links), which is what the rights confirmation covers. Picking "No" here is
technically inaccurate and risks a rejection if a reviewer notices imported
retailer imagery.

---

## 8. Age Rating (questionnaire → results in **4+**)

Answer every content-descriptor question **None / No**:

| Question | Answer |
|----------|--------|
| Cartoon or Fantasy Violence | None |
| Realistic Violence | None |
| Prolonged Graphic/Sadistic Violence | None |
| Sexual Content or Nudity | None |
| Profanity or Crude Humor | None |
| Mature/Suggestive Themes | None |
| Horror/Fear Themes | None |
| Medical/Treatment Information | None |
| Alcohol, Tobacco, or Drug Use | None |
| **Simulated Gambling** | **None** |
| **Contests** | **No** |
| Unrestricted Web Access | **No** ¹ |
| Made for Kids | No |

**Result: 4+**

¹ **Unrestricted Web Access** — answer **No** only if the app opens product links
in external Safari and has **no built-in/in-app web browser**. If Wishiz embeds a
WKWebView that loads arbitrary URLs, Apple wants **Yes**, which forces a **17+**
rating. Confirm before answering.

---

## ⚠️ Bonus blockers to fix before / during review

These are separate from the fields above but commonly stop approval:

1. **App Privacy "nutrition labels"** (App Store Connect → App Privacy — separate
   from the Privacy Policy URL). Wishiz **does collect data**, so don't pick "Not
   Collected". Declare:
   - **Contact Info** → Email Address, Name → *App Functionality* → **not** used
     for tracking, **linked** to identity.
   - **User Content** → Other User Content (wishlists, imported links, photos) →
     *App Functionality* → linked to identity, not for tracking.
   - **Identifiers / Usage Data / Tracking** → **No** (the app ships no
     analytics, ads, or tracking SDKs).

2. **Account deletion (Apple Guideline 5.1.1(v)) — likely rejection risk.** The
   app supports account creation but has **no in-app "Delete my account" flow**,
   which Apple now requires. The privacy/support pages tell users to email for
   deletion, but Apple usually wants an **in-app** path. Add a delete-account
   button (calls a new `DELETE /auth/account` endpoint) before submitting, or be
   ready for a reviewer to ask.

3. **Deep links run against the `run.app` host.** `wishiz.app` was never mapped to
   Cloud Run, so iOS Universal Links / Android App Links are bound to
   `wishiz-api-pdst26qeja-ey.a.run.app/lists/*`, whose `apple-app-site-association`
   + `assetlinks.json` the API serves. Caveats: `run.app` is a public-suffix domain
   so on-device `autoVerify` can be flaky (the `wishiz://` custom scheme + the web
   landing page's JS handoff cover the fallback), and Android `autoVerify` also
   needs the Play App Signing SHA-256 set in
   `ANDROID_APP_LINK_SHA256_CERT_FINGERPRINT` (ADR-0005).
