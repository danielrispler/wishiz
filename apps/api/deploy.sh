#!/usr/bin/env bash
#
# deploy.sh — stand up the full Wishiz GCP topology (ADR-0003 + ADR-0004).
#
# Idempotent: re-running reconciles to the same state (create-or-update, IAM
# add-binding is add-idempotent). Every gcloud call is explicit about
# --project / --quiet; regional resources pass --region or --location.
#
# What it provisions, in order:
#   1. Enable cloudtasks + cloudscheduler APIs.
#   2. Dedicated least-privilege service accounts + secret access.
#   3. Build + push the two images to Artifact Registry (Cloud Build).
#   4. wishiz-migrate Job -> execute --wait (pre-deploy schema).
#   5. wishiz-api + wishiz-scraper services.
#   6. Cloud Tasks queue + enqueuer / invoker IAM.
#   7. Wire api -> scraper live dispatch (the fail-fast trio).
#   8. wishiz-weekly-batch Job + one weekly Cloud Scheduler trigger.
#
# PREREQUISITE: these secrets must already exist in Secret Manager:
#   - supabase-connection-string  (the Supabase 6543 pooler DATABASE_URL)
#   - ZENROWS_API_KEY
# INTERNAL_API_KEY is created here with a generated value if absent.
#
# This script PROVISIONS IAM. Run it yourself — an automated agent cannot.
#
set -euo pipefail

# ---- Config -----------------------------------------------------------------
PROJECT="whishiz"
REGION="europe-west3"
AR_REPO="cloud-run-source-deploy"
AR_HOST="${REGION}-docker.pkg.dev"
IMG_BASE="${AR_HOST}/${PROJECT}/${AR_REPO}"
TAG="$(git rev-parse --short HEAD 2>/dev/null || echo manual)"
API_IMG="${IMG_BASE}/wishiz-api:${TAG}"
SCRAPER_IMG="${IMG_BASE}/wishiz-scraper:${TAG}"

# Runtime + invoker service accounts.
API_SA="wishiz-api-sa@${PROJECT}.iam.gserviceaccount.com"
SCRAPER_SA="wishiz-scraper-sa@${PROJECT}.iam.gserviceaccount.com"
TASKS_INVOKER_SA="wishiz-tasks-invoker@${PROJECT}.iam.gserviceaccount.com"
SCHEDULER_SA="wishiz-scheduler-sa@${PROJECT}.iam.gserviceaccount.com"

# Secrets (names in Secret Manager).
SECRET_DB="supabase-connection-string"
SECRET_ZENROWS="ZENROWS_API_KEY"
SECRET_INTERNAL="INTERNAL_API_KEY"

# Resource names.
QUEUE="wishiz-imports"
QUEUE_PATH="projects/${PROJECT}/locations/${REGION}/queues/${QUEUE}"
WEEKLY_JOB="wishiz-weekly-batch"
MIGRATE_JOB="wishiz-migrate"
BUCKET="wishiz-os"

# Connection-cap note: keep Σ(api_max + scraper_max + job runs) × DB_MAX_CONNS
# under the Supabase pooler client cap. With the values below: (10+5+1)×5 = 80.
DB_MAX_CONNS="5"

G="gcloud --project=${PROJECT} --quiet"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

# ---- Helpers (idempotent) ---------------------------------------------------
ensure_sa() { # <account-id> <display>
  local email="${1}@${PROJECT}.iam.gserviceaccount.com"
  if ! $G iam service-accounts describe "${email}" >/dev/null 2>&1; then
    $G iam service-accounts create "${1}" --display-name="${2}"
  fi
}

grant_secret() { # <secret> <sa-email>
  $G secrets add-iam-policy-binding "${1}" \
    --member="serviceAccount:${2}" \
    --role="roles/secretmanager.secretAccessor" >/dev/null
}

ensure_secret_random() { # <secret> — create with a generated value if absent
  if ! $G secrets describe "${1}" >/dev/null 2>&1; then
    log "Creating secret ${1} with a generated value"
    openssl rand -hex 32 | $G secrets create "${1}" --data-file=- --replication-policy=automatic
  fi
}

# ---- 1. APIs ----------------------------------------------------------------
log "Enabling Cloud Tasks + Cloud Scheduler APIs"
$G services enable cloudtasks.googleapis.com cloudscheduler.googleapis.com \
  run.googleapis.com artifactregistry.googleapis.com cloudbuild.googleapis.com \
  secretmanager.googleapis.com

# ---- 2. Service accounts + secret access ------------------------------------
log "Provisioning service accounts"
ensure_sa "wishiz-api-sa"       "Wishiz api service runtime"
ensure_sa "wishiz-scraper-sa"   "Wishiz scraper + weekly-batch runtime"
ensure_sa "wishiz-tasks-invoker" "Cloud Tasks -> scraper OIDC invoker"
ensure_sa "wishiz-scheduler-sa" "Cloud Scheduler -> weekly-batch Job runner"

ensure_secret_random "${SECRET_INTERNAL}"

log "Granting secret access"
grant_secret "${SECRET_DB}"       "${API_SA}"
grant_secret "${SECRET_INTERNAL}" "${API_SA}"
grant_secret "${SECRET_DB}"       "${SCRAPER_SA}"
grant_secret "${SECRET_ZENROWS}"  "${SCRAPER_SA}"
grant_secret "${SECRET_INTERNAL}" "${SCRAPER_SA}"

# api mints the live-import Cloud Task's OIDC token AS the tasks-invoker SA,
# so it must be allowed to act as it.
$G iam service-accounts add-iam-policy-binding "${TASKS_INVOKER_SA}" \
  --member="serviceAccount:${API_SA}" \
  --role="roles/iam.serviceAccountUser" >/dev/null

# ---- 3. Build + push both images (Cloud Build) ------------------------------
# Build context is apps/api (this script's dir) because the Dockerfiles COPY
# go.mod/go.sum then the source relative to it.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log "Building images via Cloud Build (tag ${TAG})"
CB_CFG="$(mktemp)"
trap 'rm -f "${CB_CFG}"' EXIT
cat >"${CB_CFG}" <<YAML
steps:
  - name: gcr.io/cloud-builders/docker
    args: ['build', '-t', '${API_IMG}', '-f', 'Dockerfile.api', '.']
  - name: gcr.io/cloud-builders/docker
    args: ['build', '-t', '${SCRAPER_IMG}', '-f', 'Dockerfile.scraper', '.']
images:
  - '${API_IMG}'
  - '${SCRAPER_IMG}'
options:
  logging: CLOUD_LOGGING_ONLY
YAML
$G builds submit "${SCRIPT_DIR}" --config="${CB_CFG}"

# ---- 4. Migrate Job (pre-deploy) --------------------------------------------
log "Reconciling + executing the migrate Job"
if $G run jobs describe "${MIGRATE_JOB}" --region="${REGION}" >/dev/null 2>&1; then
  $G run jobs update "${MIGRATE_JOB}" --region="${REGION}" \
    --image="${API_IMG}" --service-account="${API_SA}" \
    --set-env-vars="SERVICE_ROLE=migrate,APP_ENV=production" \
    --set-secrets="DATABASE_URL=${SECRET_DB}:latest"
else
  $G run jobs create "${MIGRATE_JOB}" --region="${REGION}" \
    --image="${API_IMG}" --service-account="${API_SA}" \
    --set-env-vars="SERVICE_ROLE=migrate,APP_ENV=production" \
    --set-secrets="DATABASE_URL=${SECRET_DB}:latest" \
    --max-retries=0 --task-timeout=600s
fi
$G run jobs execute "${MIGRATE_JOB}" --region="${REGION}" --wait

# ---- 5. Services ------------------------------------------------------------
log "Deploying wishiz-api"
$G run deploy wishiz-api --region="${REGION}" \
  --image="${API_IMG}" --service-account="${API_SA}" \
  --allow-unauthenticated \
  --min-instances=0 --max-instances=10 --cpu-boost \
  --set-env-vars="SERVICE_ROLE=api,APP_ENV=production,DB_MAX_CONNS=${DB_MAX_CONNS},UPLOADS_ENABLED=true,BUCKET_NAME=${BUCKET},GCS_PUBLIC_BASE_URL=https://storage.googleapis.com" \
  --set-secrets="DATABASE_URL=${SECRET_DB}:latest,INTERNAL_API_KEY=${SECRET_INTERNAL}:latest"

log "Deploying wishiz-scraper"
$G run deploy wishiz-scraper --region="${REGION}" \
  --image="${SCRAPER_IMG}" --service-account="${SCRAPER_SA}" \
  --no-allow-unauthenticated \
  --memory=2Gi --cpu=2 --timeout=300 \
  --min-instances=0 --max-instances=5 --cpu-boost \
  --execution-environment=gen2 \
  --set-env-vars="SERVICE_ROLE=scraper,APP_ENV=production,DB_MAX_CONNS=${DB_MAX_CONNS}" \
  --set-secrets="DATABASE_URL=${SECRET_DB}:latest,ZENROWS_API_KEY=${SECRET_ZENROWS}:latest,INTERNAL_API_KEY=${SECRET_INTERNAL}:latest"

SCRAPER_URL="$($G run services describe wishiz-scraper --region="${REGION}" \
  --format='value(status.url)')"
log "scraper URL: ${SCRAPER_URL}"

# ---- 6. Cloud Tasks queue + IAM ---------------------------------------------
log "Reconciling Cloud Tasks queue"
if ! $G tasks queues describe "${QUEUE}" --location="${REGION}" >/dev/null 2>&1; then
  $G tasks queues create "${QUEUE}" --location="${REGION}"
fi
$G tasks queues update "${QUEUE}" --location="${REGION}" \
  --max-attempts=5 --min-backoff=10s --max-backoff=300s --max-doublings=3

# api enqueues; tasks-invoker is allowed to invoke the (private) scraper.
$G tasks queues add-iam-policy-binding "${QUEUE}" --location="${REGION}" \
  --member="serviceAccount:${API_SA}" --role="roles/cloudtasks.enqueuer" >/dev/null
$G run services add-iam-policy-binding wishiz-scraper --region="${REGION}" \
  --member="serviceAccount:${TASKS_INVOKER_SA}" --role="roles/run.invoker" >/dev/null

# ---- 7. Wire api live dispatch (fail-fast trio) -----------------------------
log "Wiring api -> Cloud Tasks dispatch"
$G run services update wishiz-api --region="${REGION}" \
  --update-env-vars="IMPORT_TASKS_QUEUE=${QUEUE_PATH},SCRAPER_URL=${SCRAPER_URL},SCRAPER_AUDIENCE=${SCRAPER_URL},SCRAPER_INVOKER_SA=${TASKS_INVOKER_SA}"

# ---- 8. weekly-batch Job + Cloud Scheduler ----------------------------------
log "Reconciling weekly-batch Job"
if $G run jobs describe "${WEEKLY_JOB}" --region="${REGION}" >/dev/null 2>&1; then
  $G run jobs update "${WEEKLY_JOB}" --region="${REGION}" \
    --image="${SCRAPER_IMG}" --service-account="${SCRAPER_SA}" \
    --set-env-vars="SERVICE_ROLE=weekly-batch,APP_ENV=production,DB_MAX_CONNS=${DB_MAX_CONNS}" \
    --set-secrets="DATABASE_URL=${SECRET_DB}:latest,ZENROWS_API_KEY=${SECRET_ZENROWS}:latest"
else
  $G run jobs create "${WEEKLY_JOB}" --region="${REGION}" \
    --image="${SCRAPER_IMG}" --service-account="${SCRAPER_SA}" \
    --memory=2Gi --cpu=2 --max-retries=1 --task-timeout=3600s \
    --set-env-vars="SERVICE_ROLE=weekly-batch,APP_ENV=production,DB_MAX_CONNS=${DB_MAX_CONNS}" \
    --set-secrets="DATABASE_URL=${SECRET_DB}:latest,ZENROWS_API_KEY=${SECRET_ZENROWS}:latest"
fi

# Scheduler executes the Job via the Run Admin API (OAuth, cloud-platform scope).
$G run jobs add-iam-policy-binding "${WEEKLY_JOB}" --region="${REGION}" \
  --member="serviceAccount:${SCHEDULER_SA}" --role="roles/run.invoker" >/dev/null

RUN_JOB_URI="https://${REGION}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${PROJECT}/jobs/${WEEKLY_JOB}:run"
log "Reconciling weekly Cloud Scheduler trigger (Mon 03:00 UTC)"
if $G scheduler jobs describe "${WEEKLY_JOB}-trigger" --location="${REGION}" >/dev/null 2>&1; then
  SCHED_VERB="update"
else
  SCHED_VERB="create"
fi
$G scheduler jobs "${SCHED_VERB}" http "${WEEKLY_JOB}-trigger" --location="${REGION}" \
  --schedule="0 3 * * 1" --time-zone="Etc/UTC" \
  --uri="${RUN_JOB_URI}" --http-method=POST \
  --oauth-service-account-email="${SCHEDULER_SA}" \
  --oauth-token-scope="https://www.googleapis.com/auth/cloud-platform"

# ---- Done -------------------------------------------------------------------
API_URL="$($G run services describe wishiz-api --region="${REGION}" --format='value(status.url)')"
cat <<DONE

============================================================
Deploy complete.
  api     : ${API_URL}
  scraper : ${SCRAPER_URL}  (private; Cloud Tasks only)
  images  : ${TAG}
  weekly  : ${WEEKLY_JOB} (Mon 03:00 UTC) -> maintenance + crawl + drain
============================================================
Note: the legacy single 'wishiz' service is now superseded; retire it and its
Dockerfile.api-only build trigger when you're confident in the split.
DONE
