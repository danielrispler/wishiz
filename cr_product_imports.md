# Code Review: Asynchronous Product Import System

## [HIGH] Architectural Coupling: UI-Driven Polling
- **Why this is a problem**: The polling logic (`_importPollTimer`, `_refreshImportJobs`) is implemented directly inside `_HomeScreenState`. This creates a tight coupling between the Home UI and a core business process.
- **Where it appears**: `apps/mobile/lib/features/home/presentation/screens/home_screen.dart` (Lines 74, 86-100)
- **What will happen if not fixed**: 
  - If the user navigates away from `HomeScreen` (e.g., to Account or Reminders), polling stops. 
  - Status updates for imports won't be received while the app is on other screens.
  - Adding a second entry point for imports (e.g., from a deep link or another screen) would require duplicating this logic.
- **Recommended fix**: Move the polling/synchronization logic into a dedicated service (e.g., `ProductImportSyncService`) or handle it within the `ProductImportRepository` implementation. The repository should expose a `Stream<List<ProductImportJob>>` (instead of just `ValueListenable`) that internally manages the polling lifecycle independent of the UI.

## [MEDIUM] UI Scalability: Large Widget Methods
- **Why this is a problem**: `_HomeScreenState` has grown significantly with the addition of `_buildImportQueue`, `_buildImportJobRow`, `_jobStatusIcon`, and `_jobActions`. This makes the file harder to maintain and increases the risk of side effects during rebuilds.
- **Where it appears**: `apps/mobile/lib/features/home/presentation/screens/home_screen.dart` (Lines 493-691)
- **What will happen if not fixed**: "God object" screens are difficult to test and refactor. Rebuilds of the import queue will trigger checks in the entire `HomeScreen` widget tree.
- **Recommended fix**: Extract the import queue components into their own widget files (e.g., `ImportQueueView` and `ImportJobTile`) in `features/product_imports/presentation/widgets/`.

## [MEDIUM] UX: Manual Acknowledgment vs. Auto-Dismiss
- **Why this is a problem**: Completed jobs require manual acknowledgment (`_acknowledgeImportJob`) via a close button to disappear from the queue. While good for visibility, it adds friction for "perfect" imports that the user might just want to see in their list immediately.
- **Where it appears**: `apps/mobile/lib/features/home/presentation/screens/home_screen.dart` (Line 670)
- **What will happen if not fixed**: The Home screen becomes cluttered with "stale" completed jobs until the user manually cleans them up.
- **Recommended fix**: Consider auto-acknowledging/hiding "completed" jobs after a short duration (e.g., 30 seconds) if the user has seen them, or provide a "Clear All Completed" button.

## [LOW] Performance: Inefficient Polling Duration
- **Why this is a problem**: A fixed 5-second polling interval is used whenever *any* job is active.
- **Where it appears**: `apps/mobile/lib/features/home/presentation/screens/home_screen.dart` (Line 99)
- **What will happen if not fixed**: Minor unnecessary battery drain and server load, especially if the scraping process is known to take longer (e.g., 15-30s).
- **Recommended fix**: Implement exponential backoff for polling if jobs stay in `pending` or `processing` for a long time, or ideally, move to a push-based system (WebSockets/FCM) if the backend supports it.

## [LOW] Code Safety: Default Values in Domain Entities
- **Why this is a problem**: `Wishlist.ownerFullName` was changed from `required` to having a default empty string. 
- **Where it appears**: `apps/mobile/lib/features/wishlists/domain/entities/wishlist.dart` (Line 10)
- **What will happen if not fixed**: This hides potential data issues where the owner's name is missing from the API response. It’s better to handle "missing" data at the mapping layer rather than the domain layer.
- **Recommended fix**: Keep it `required` and ensure the DTO-to-Entity mapper provides a fallback or handles the nullability explicitly.

---

# ARCHITECTURAL VERDICT: WITH RISKS

This code implements a much-needed asynchronous flow for product scraping, which significantly improves the UX by not blocking the main thread. However, the **UI-driven polling** is a significant technical debt.

### MUST be fixed before continuing:
1. **Decouple Sync Logic**: The `Timer` must be moved out of the `HomeScreen` state and into a service or the repository to ensure status updates happen regardless of which screen is currently visible.
2. **Widget Extraction**: The `HomeScreen` is becoming too bloated; the new import UI logic should be moved to the `product_imports` feature directory.
