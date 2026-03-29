# Wishiz App Completion Plan

## Goal

Complete the Wishiz app by **keeping the current visual design, typography, and color palette** and adding the missing product functionality behind it.

## Current State Audit

The codebase is currently a strong design shell, not a finished application.

What already exists:

- A working Flutter entry point and app theme.
- A clear design system in `lib/core/theme`.
- A polished home screen with:
  - brand header
  - wishlist summary cards
  - a glassmorphic bottom navigation
  - a primary "Create List" call to action

What is still missing:

- No real data models.
- No local or remote persistence.
- No repository or service layer.
- No functional list creation flow.
- No list detail screen.
- No item creation, editing, deleting, or sorting.
- No shared lists feature.
- No past lists feature.
- No search, filters, or empty states beyond placeholders.
- No tests.

## Important Constraint

The current code does **not** expose the actual Wishiz Figma file. The configured Figma MCP server is authenticated, but no Wishiz design document or node URL is accessible from this workspace yet.

That means this plan is grounded in the existing Flutter code and screen labels, but **exact screen parity with Figma still requires a Figma file URL or node URL**.

## Design Preservation Rules

Keep these parts stable while implementing functionality:

- `lib/core/theme/app_colors.dart`
- `lib/core/theme/app_typography.dart`
- `lib/core/theme/app_theme.dart`
- The current spacing and rounded-corner language in `lib/core/constants/app_constants.dart`
- The editorial layout and glassmorphic navigation style already used on the home screen

In practice:

- Add behavior first.
- Only change layout when a functional screen needs it.
- Reuse existing tones and typography tokens instead of introducing new visual styles.

## Recommended Product Scope

Based on the current app structure, the likely core product should include:

1. My Lists
2. Create List
3. List Details
4. Add and manage wishlist items
5. Shared Lists
6. Past Lists / archived lists
7. Basic search and filtering

## Recommended Data Model

### Wishlist

- `id`
- `title`
- `description`
- `coverImageUrl`
- `createdAt`
- `updatedAt`
- `isArchived`
- `isShared`

### WishlistItem

- `id`
- `wishlistId`
- `title`
- `notes`
- `price`
- `currency`
- `imageUrl`
- `productUrl`
- `priority`
- `status`
- `createdAt`
- `updatedAt`

### SharedUser

- `id`
- `name`
- `email`
- `role`

## Recommended Architecture

Keep the feature-based structure, but add actual layers:

```text
lib/
  core/
  features/
    home/
    wishlists/
      data/
      domain/
      presentation/
    shared_lists/
      data/
      domain/
      presentation/
    archived_lists/
      data/
      domain/
      presentation/
```

Recommended additions:

- State management: `flutter_riverpod`
- Navigation: `go_router`
- Local persistence for MVP: `hive` or `isar`
- Utility packages as needed:
  - `uuid`
  - `intl`
  - `equatable`

## Build Order

### Phase 1: Turn the mockup into a real local app

Deliverable:
The app works fully offline with real list and item CRUD.

Steps:

1. Add app models for `Wishlist` and `WishlistItem`.
2. Add a local repository with seeded demo data.
3. Replace hardcoded cards in `HomeScreen` with repository-backed state.
4. Make "Create List" open a real create-list screen or modal.
5. Add validation for required list fields.
6. Add a list detail screen.
7. Let users add, edit, and delete items from a list.
8. Add empty states for:
   - no lists
   - no items
   - no shared lists
   - no archived lists

### Phase 2: Finish the bottom navigation sections

Deliverable:
All three tabs work as real features.

Steps:

1. `My lists`:
   - show all active lists
   - support open, create, rename, delete, archive
2. `Shared`:
   - show shared lists
   - show owner or collaborator metadata
   - allow invite UI, even if backend sync comes later
3. `Past lists`:
   - show archived lists
   - allow restore or permanent delete

### Phase 3: Add product polish that users expect

Deliverable:
The app feels complete rather than just functional.

Steps:

1. Search lists by title.
2. Filter items by status or priority.
3. Support wishlist item links and price fields.
4. Add confirm dialogs for destructive actions.
5. Add loading, error, and success feedback states.
6. Add basic accessibility improvements:
   - semantic labels
   - larger touch targets
   - contrast validation

### Phase 4: Prepare for sharing and sync

Deliverable:
The codebase is ready for backend integration.

Steps:

1. Separate repository interfaces from local implementations.
2. Add DTO or serializer boundaries.
3. Define sync-safe IDs and timestamps.
4. Add placeholders for:
   - auth
   - collaboration
   - remote sync

## Screen-Level Work Needed

### Home Screen

Current status:
Visual only, using hardcoded data and snackbars.

Needs:

- dynamic list summaries
- quick create flow
- navigation into list details
- recent activity or updated state from real data

### Create List Flow

Needs:

- title input
- optional description
- optional cover image or icon
- save and cancel actions
- validation and feedback

### List Detail Screen

Needs:

- list title and metadata
- item gallery or list layout
- add item button
- edit list action
- archive list action

### Shared Tab

Needs:

- shared list collection
- collaborator metadata
- invite/share entry point
- empty state

### Past Lists Tab

Needs:

- archived list collection
- restore action
- delete action
- empty state

## Priority Checklist

If you want the shortest path to a usable app, do these first:

1. Create real models.
2. Add local persistence.
3. Replace hardcoded home data.
4. Build create-list flow.
5. Build list-detail flow.
6. Add item CRUD.
7. Make Shared and Past tabs real.

## Suggested First Implementation Sprint

Sprint goal:
Ship a fully usable offline MVP without changing the design language.

Tasks:

1. Add `Wishlist` and `WishlistItem` entities.
2. Add a local in-memory repository first, then persistence.
3. Refactor `HomeScreen` to read from state instead of hardcoded widgets.
4. Build a `CreateListScreen`.
5. Build a `WishlistDetailScreen`.
6. Add item create and delete actions.
7. Replace placeholder tabs with real feature screens.

## Risks To Avoid

- Do not start with backend integration before local flows work.
- Do not redesign the visual system while adding functionality.
- Do not keep feature logic inside one screen file.
- Do not leave the bottom tabs as placeholders while building advanced features.

## Exact Next Step

The best next implementation step is:

1. Create the `wishlists` feature module with entities, repository interfaces, and local seeded data.
2. Refactor the current `HomeScreen` to render real lists from that state.
3. Build the create-list and list-detail flows next.

## Figma Blocker For Full Fidelity

To match the full app exactly as designed, provide one of these:

- a Figma file URL
- a Figma node URL
- the file key

Once that is available, this plan can be tightened into an exact screen-by-screen parity checklist.
