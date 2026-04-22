# Wishiz Agent Guidelines

Welcome! This `AGENT.md` file provides context and strict guidelines for any AI agent operating within the Wishiz monorepo.

## Project Context

This is a monorepo containing the following key components:
- **`apps/mobile`**: The Wishiz mobile application, built with Flutter.
- **`apps/api`**: The backend API, built with Go.
- **`contracts/openapi`**: API contracts and specifications.
- **`infra`**: Infrastructure-related configuration.

## 🛑 Strict Task Completion Protocol

**CRITICAL: Before finishing any task, you MUST verify your changes by running the appropriate build, test, and lint commands.**

Never assume the code works just by looking at it. You must prove it works and passes CI checks locally. Depending on the directories you have modified, execute the corresponding verification steps:

### If you modified `apps/mobile`:
Navigate to `apps/mobile` and run:
```bash
cd apps/mobile
flutter pub get
flutter analyze   # Lint
flutter test      # Test
flutter build apk # Verify Build (or run appropriate build command)
```

### If you modified `apps/api`:
Navigate to `apps/api` and run:
```bash
cd apps/api
make lint         # Lint
make test         # Test
go build ./...    # Verify Build
```

If any of these verification steps fail, you **must** resolve the errors and run the checks again until they pass. Only then can you report that the task is finished.
