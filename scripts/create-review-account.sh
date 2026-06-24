#!/usr/bin/env bash
#
# create-review-account.sh
#
# Creates (and seeds) the Apple App Review demo account against the Wishiz API,
# then prints the credentials to paste into App Store Connect under
#   App Review Information -> Sign-In Information.
#
# The shipped iOS build points at the production Cloud Run API by default, so this
# must run against prod for the reviewer to be able to sign in. Override the target
# with WISHIZ_API_BASE_URL to run it against local docker-compose instead.
#
# Auth is plain email+password (no 2FA / no email verification), so the reviewer
# signs in with nothing but the two strings printed at the end. Sessions last 30
# days; the account itself never expires.
#
# Usage:
#   REVIEW_ACCOUNT_PASSWORD='a-strong-password' ./scripts/create-review-account.sh
#
# Optional env overrides:
#   WISHIZ_API_BASE_URL   API base URL          (default: prod Cloud Run host)
#   REVIEW_ACCOUNT_EMAIL  demo account email    (default: appreview@wishiz.app)
#   REVIEW_ACCOUNT_NAME   demo account name     (default: "Apple Reviewer")
#
# Re-runs are idempotent: if the account already exists (HTTP 409) the script logs
# in instead of re-seeding, so wishlists never get duplicated.

set -euo pipefail

BASE="${WISHIZ_API_BASE_URL:-https://wishiz-api-pdst26qeja-ey.a.run.app}"
EMAIL="${REVIEW_ACCOUNT_EMAIL:-appreview@wishiz.app}"
PASSWORD="${REVIEW_ACCOUNT_PASSWORD:-}"
FULL_NAME="${REVIEW_ACCOUNT_NAME:-Apple Reviewer}"

if [[ -z "$PASSWORD" ]]; then
  echo "ERROR: REVIEW_ACCOUNT_PASSWORD is required." >&2
  echo "Usage: REVIEW_ACCOUNT_PASSWORD='a-strong-password' $0" >&2
  exit 1
fi

# api <METHOD> <PATH> <JSON_BODY|''> [BEARER_TOKEN]
# Echoes the response body followed by a final line containing the HTTP status.
api() {
  local method="$1" path="$2" data="$3" token="${4:-}"
  local args=(-sS -X "$method" "$BASE$path" -H 'Content-Type: application/json'
              -w $'\n%{http_code}')
  [[ -n "$data" ]] && args+=(-d "$data")
  [[ -n "$token" ]] && args+=(-H "Authorization: Bearer $token")
  curl "${args[@]}"
}

# json_str <body> <key> -> first string value for "key" (no jq dependency)
json_str() {
  printf '%s' "$1" | grep -o "\"$2\":\"[^\"]*\"" | head -1 |
    sed "s/\"$2\":\"\\(.*\\)\"/\\1/"
}

status_of() { tail -n1 <<<"$1"; }
body_of()   { sed '$d' <<<"$1"; }

echo "Target API: $BASE"
echo "Account:    $EMAIL"
echo

# ---------------------------------------------------------------------------
# Step 1 — sign up (or log in if it already exists)
# ---------------------------------------------------------------------------
signup_payload=$(cat <<JSON
{
  "email": "$EMAIL",
  "password": "$PASSWORD",
  "fullName": "$FULL_NAME",
  "birthday": "1990-01-01T00:00:00Z",
  "gender": "woman",
  "preferredCurrencyCode": "USD",
  "notificationsEnabled": true,
  "reminderDays": 14
}
JSON
)

resp="$(api POST /auth/signup "$signup_payload")"
status="$(status_of "$resp")"
body="$(body_of "$resp")"

SEED=true
case "$status" in
  201)
    echo "Created account (HTTP 201)."
    ;;
  409)
    echo "Account already exists (HTTP 409) — logging in, skipping re-seed."
    resp="$(api POST /auth/login "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")"
    status="$(status_of "$resp")"
    body="$(body_of "$resp")"
    if [[ "$status" != "200" ]]; then
      echo "ERROR: login failed (HTTP $status): $body" >&2
      echo "(The account exists but the password differs from REVIEW_ACCOUNT_PASSWORD.)" >&2
      exit 1
    fi
    SEED=false
    ;;
  *)
    echo "ERROR: signup failed (HTTP $status): $body" >&2
    exit 1
    ;;
esac

TOKEN="$(json_str "$body" token)"
if [[ -z "$TOKEN" ]]; then
  echo "ERROR: could not extract session token from response: $body" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Step 2/3 — seed wishlists + items (only on a freshly created account)
# ---------------------------------------------------------------------------
create_wishlist() { # <title> <description> <year> -> echoes wishlist id
  local r s b
  r="$(api POST /wishlists "{\"title\":\"$1\",\"description\":\"$2\",\"year\":$3}" "$TOKEN")"
  s="$(status_of "$r")"; b="$(body_of "$r")"
  if [[ "$s" != "201" && "$s" != "200" ]]; then
    echo "ERROR: create wishlist '$1' failed (HTTP $s): $b" >&2
    exit 1
  fi
  json_str "$b" id
}

add_item() { # <wishlistID> <title> <priceLabel> <priority> <status> <imageUrl> <productUrl>
  local r s b
  r="$(api POST "/wishlists/$1/items" \
    "{\"title\":\"$2\",\"priceLabel\":\"$3\",\"priority\":\"$4\",\"status\":\"$5\",\"imageUrl\":\"$6\",\"productUrl\":\"$7\"}" \
    "$TOKEN")"
  s="$(status_of "$r")"; b="$(body_of "$r")"
  if [[ "$s" != "201" && "$s" != "200" ]]; then
    echo "ERROR: add item '$2' failed (HTTP $s): $b" >&2
    exit 1
  fi
  echo "    + $2"
}

if [[ "$SEED" == true ]]; then
  echo
  echo "Seeding wishlists..."

  IMG="?auto=format&fit=crop&w=800&q=80"

  echo "  Wishlist: Birthday 2026"
  W1="$(create_wishlist "Birthday 2026" "Things I'm dreaming about this year." 2026)"
  add_item "$W1" "Wireless Headphones" "\$349" "high"   "saved" \
    "https://images.unsplash.com/photo-1505740420928-5e560c06d30e$IMG" \
    "https://www.apple.com/airpods-max/"
  add_item "$W1" "Running Sneakers"    "\$120" "medium" "considering" \
    "https://images.unsplash.com/photo-1542291026-7eec264c27ff$IMG" \
    "https://www.nike.com/"
  add_item "$W1" "Minimalist Watch"    "\$199" "low"    "saved" \
    "https://images.unsplash.com/photo-1523275335684-37898b6baf30$IMG" \
    "https://www.danielwellington.com/"

  echo "  Wishlist: Home Wishlist"
  W2="$(create_wishlist "Home Wishlist" "Cozy upgrades for the apartment." 2026)"
  add_item "$W2" "Scented Candle" "\$32"  "medium" "saved" \
    "https://images.unsplash.com/photo-1602874801007-bd458bb1b8b6$IMG" \
    "https://www.diptyqueparis.com/"
  add_item "$W2" "Ceramic Mug Set" "\$45" "low"    "considering" \
    "https://images.unsplash.com/photo-1514228742587-6b1558fcca3d$IMG" \
    "https://www.westelm.com/"
  add_item "$W2" "Indoor Plant"    "\$28" "low"    "purchased" \
    "https://images.unsplash.com/photo-1485955900006-10f4d324d411$IMG" \
    "https://www.thesill.com/"

  echo "Seeding complete."
fi

# ---------------------------------------------------------------------------
# Done — print credentials for App Store Connect
# ---------------------------------------------------------------------------
cat <<SUMMARY

========================================================================
  App Store Connect -> App Review Information -> Sign-In Information
------------------------------------------------------------------------
  Keep "Sign-in required" CHECKED.

    User name:  $EMAIL
    Password:   $PASSWORD

  API: $BASE
========================================================================
SUMMARY
