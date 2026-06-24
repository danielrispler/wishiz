# App store identifier is `com.wishiz` on both platforms

## Status

accepted

## Decision

The published application identifier is **`com.wishiz`** on both Google Play and
the Apple App Store. Both platforms share the single id.

- **Android**: `applicationId`/`namespace` move from Flutter's placeholder
  `com.example.wishiz` to `com.wishiz` (`apps/mobile/android/app/build.gradle.kts`;
  Kotlin sources move to the matching `com/wishiz/` package dir).
- **iOS**: the bundle id is renamed `com.wishiz.beta` → `com.wishiz` (Runner +
  ShareExtension `com.wishiz.ShareExtension`), and the app group
  `group.com.wishiz.beta.shared` → `group.com.wishiz.app.shared` (the bare
  `group.com.wishiz.shared` was already taken in the Apple Developer Portal).
- **Server**: the deep-link descriptors served from `apps/api/cmd/api/main.go`
  carry `AndroidPackageName: "com.wishiz"` and `IOSAppID:
  "P46VR4C98R.com.wishiz"`, so Android App Links + iOS Universal Links keep
  verifying after the rename.

## Context

The mobile app was not store-shippable: Android still carried Flutter's
`com.example.*` placeholder (banned on Google Play), and iOS had only ever been
uploaded under the beta id `com.wishiz.beta` (TestFlight, **no real testers**).
Shipping required picking a permanent production id. Two candidates:

- **`app.wishiz`** — derived from the product domain `wishiz.app` (reverse-DNS of
  the domain we actually own), the more conventional choice.
- **`com.wishiz`** — a clean, conventional `com.` id, identical across both stores.

`com.wishiz` was chosen for cross-platform consistency and a clean production id.
The trade-off accepted: it does **not** match the `wishiz.app` domain (so a future
reader expecting reverse-domain-of-the-website will be surprised), and on iOS it
means **abandoning the already-uploaded `com.wishiz.beta`** App Store Connect
record / App ID. Abandoning it is cheap because that record has no real testers;
its orphaned `group.com.wishiz.beta.shared` data is throwaway.

This is recorded as an ADR because it is **hard to reverse** (an app id is
permanent once published on either store) and **surprising** (domain-derived
`app.wishiz` would be the default guess; the iOS beta record is discarded).

## Consequences

- A fresh Apple App ID `com.wishiz`, App Store Connect app record, and App Group
  `group.com.wishiz.app.shared` must be registered; the old `com.wishiz.beta` artifacts
  are left to rot.
- Android deep-link verification is finalized **post-upload**: Play App Signing
  holds the app-signing cert, whose SHA-256 is only visible after the first AAB
  upload. Until `ANDROID_APP_LINK_SHA256_CERT_FINGERPRINT` is overridden in the
  prod deploy with Google's value, `https://wishiz-api-pdst26qeja-ey.a.run.app/lists/*`
  links do not auto-verify on Android (config ships a stale built-in default that
  will not match).
- The associated domain is `applinks:wishiz-api-pdst26qeja-ey.a.run.app` (host-based,
  id-independent) — it moved to the Cloud Run `run.app` host because `wishiz.app`
  was never DNS-mapped; the domain choice is unaffected by the app-id choice.
- Desktop targets (macOS/Linux/Windows) still carry `com.example.wishiz`; they are
  not shipped now and would need the same rename before any desktop release.
