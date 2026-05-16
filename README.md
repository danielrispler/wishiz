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
cd apps/api
make lint
make test
```

Or run the API with Docker:

```bash
cp .env.example .env
# edit .env before first run
docker compose up --build
curl http://localhost:8080/health
```

Expected response:

```json
{"status":"ok"}
```

For a single production VM, the Compose stack now expects configuration from `.env` instead of hardcoded secrets.
`api` is exposed publicly on `:8080` by default, while MinIO and its console bind to `127.0.0.1` unless you explicitly change the bind addresses.
