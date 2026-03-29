# Wishiz Monorepo

Wishiz now lives in a small monorepo with:

- `apps/mobile`: the existing Flutter app
- `apps/api`: the new Go API scaffold
- `contracts/openapi`: lightweight API contract placeholders
- `docs`: repo-level notes
- `infra`: infrastructure-related files for future work

## Quick Start

### Mobile

```bash
cd apps/mobile
flutter pub get
flutter analyze
flutter test
```

### API

```bash
docker compose up --build
curl http://localhost:8080/health
```

Expected response:

```json
{"status":"ok"}
```
