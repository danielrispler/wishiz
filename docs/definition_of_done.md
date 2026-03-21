# Definition of Done

## Goal

Every feature in Wishiz should be considered done only when it is functional, visually aligned with the current design system, and verified against regressions.

## A Feature Is Done When

1. The user can complete the intended task end to end.
2. The feature preserves the existing Wishiz visual language:
   - current typography
   - current color palette
   - current spacing and rounded corners
   - current glassmorphic and editorial styling patterns
3. Loading, empty, success, and failure states are handled where relevant.
4. Existing flows still work after the change.
5. New logic is covered by tests when the code is testable.
6. Linting and static analysis pass.
7. The UI is manually checked for the affected flows.
8. The change is documented in a short feature summary with:
   - what was added
   - what was verified
   - what remains blocked

## Required Verification After Each Feature Slice

Run these checks after every step:

1. `flutter test`
2. `flutter analyze`
3. Launch the app and verify the affected screens manually

Manual verification should confirm:

- navigation still works
- the new flow is usable
- the current layout still matches the existing design direction
- unrelated tabs or actions were not broken

## If The Environment Blocks Verification

If `flutter` or `dart` is unavailable in the current environment:

1. still implement the feature cleanly
2. add or update the relevant tests
3. run every available verification command
4. clearly report which required checks could not be executed

## Delivery Order

Work feature by feature. A feature slice should be small enough that we can:

1. implement it
2. verify it
3. confirm regressions did not appear
4. move to the next slice with confidence
