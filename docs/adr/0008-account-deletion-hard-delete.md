# Account deletion: hard delete, cascade owned lists, password-gated

## Status

accepted

## Context

Apple App Review (Guideline 5.1.1(v)) requires an in-app way to delete an account.
We had account creation but no deletion path. The user-data graph hangs off
`app_users` with FK cascades already in place (every FK referencing a user has an
explicit `ON DELETE` — CASCADE or SET NULL), so the schema can absorb a hard
`DELETE FROM app_users` with zero referential-integrity errors.

## Decision

`DELETE /auth/me` (RequireAuth) hard-deletes the user after **bcrypt-verifying the
password from the request body**. The single `DELETE FROM app_users WHERE id` lets
the FK cascade remove sessions, owned wishlists (and their items/members/invites),
import jobs, notifications, device tokens and discover saves. Uploaded image
objects in GCS — which are stored only as URLs and not tracked per-user — are
cleaned up best-effort: the user's owned image keys are collected from `wishlists`
/`wishlist_items` (filtered to our bucket prefix; external scraped retailer URLs
are skipped) **before** the delete, and the objects removed **after** the row is
gone, so a failed delete never orphans live data. Cleanup is wired into the auth
service via a nil-safe `WithImageGC`, mirroring the `WithNotifier` pattern.

## Considered options

- **Anonymize / soft-delete** (keep the row, scrub PII, `deleted_at`) — rejected:
  Apple wants real deletion, not deactivation, and soft-delete would force a
  `deleted_at` filter through every auth/login/list query for marginal benefit.
- **Transfer ownership of shared lists before deleting** — deferred. See below.

## Consequences

- **Deleting an owner destroys their shared wishlists for everyone.** Because
  `wishlists.owner_id` is `ON DELETE CASCADE`, an owned list (and all collaborators'
  access to it) is removed with the account. This is deliberate and surfaced to the
  user via a confirmation dialog ("lists you own are removed for everyone"). It is
  **not a bug** — do not "fix" the cascade. Ownership-transfer is a possible future
  enhancement if collaborator retention becomes a requirement.
- **GCS cleanup is best-effort.** A partial failure leaves some unguessable,
  identity-detached objects behind; acceptable, logged, never blocks deletion.
- The session cascades away, so the caller's token is invalid immediately after a
  204; the mobile client clears its local session and falls back to the login gate.
