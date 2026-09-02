#!/usr/bin/env bash
set -Eeuo pipefail

REPO="/home/paulius/pauvi"
STATE_DIR="/var/lib/pauvi"
ACTIVE_FILE="$STATE_DIR/active-slot"
COMMIT_FILE="$STATE_DIR/deployed-commit"
LOCK_FILE="/run/lock/pauvi-deploy.lock"
BALANCER_CONF="/etc/apache2/conf-available/pauvi-balancers.conf"

mkdir -p "$STATE_DIR"

exec 9>"$LOCK_FILE"
flock -n 9 || {
    echo "Deploy already running."
    exit 0
}

cd "$REPO"

if [[ ! -f .env ]]; then
    echo "ERROR: $REPO/.env does not exist."
    exit 1
fi

if grep -q 'CHANGE_ME' .env; then
    echo "ERROR: .env still contains CHANGE_ME values."
    exit 1
fi

BRANCH="$(sed -n 's/^DEPLOY_BRANCH=//p' .env | tail -n1)"
BRANCH="${BRANCH:-main}"

gitp() {
    runuser -u paulius -- git -C "$REPO" "$@"
}

echo "Fetching origin/$BRANCH..."
gitp fetch --prune origin "$BRANCH"

REMOTE_COMMIT="$(gitp rev-parse "origin/$BRANCH")"
DEPLOYED_COMMIT="$(cat "$COMMIT_FILE" 2>/dev/null || true)"

FORCE="${1:-}"

if [[ "$FORCE" != "--force" && "$REMOTE_COMMIT" == "$DEPLOYED_COMMIT" ]]; then
    echo "No new commit. Nothing to deploy."
    exit 0
fi

DB_HEALTH="$(
    docker inspect \
      --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' \
      pauvi-mysql 2>/dev/null || true
)"

if [[ "$DB_HEALTH" != "healthy" ]]; then
    echo "ERROR: pauvi-mysql is not healthy: $DB_HEALTH"
    exit 1
fi

echo "Checking out $REMOTE_COMMIT..."
gitp reset --hard "origin/$BRANCH"

ACTIVE="$(cat "$ACTIVE_FILE" 2>/dev/null || echo blue)"

if [[ "$ACTIVE" == "blue" ]]; then
    TARGET="green"
    FRONTEND_PORT=8083
    BACKEND_PORT=3003

    OLD_FRONTEND_PORT=8081
    OLD_BACKEND_PORT=3001
else
    TARGET="blue"
    FRONTEND_PORT=8081
    BACKEND_PORT=3001

    OLD_FRONTEND_PORT=8083
    OLD_BACKEND_PORT=3003
fi

PROJECT="pauvi-$TARGET"

echo "Building inactive slot: $TARGET"

FRONTEND_PORT="$FRONTEND_PORT" \
BACKEND_PORT="$BACKEND_PORT" \
docker compose \
    -p "$PROJECT" \
    -f compose.app.yaml \
    --env-file .env \
    build --pull

echo "Starting inactive slot: $TARGET"

FRONTEND_PORT="$FRONTEND_PORT" \
BACKEND_PORT="$BACKEND_PORT" \
docker compose \
    -p "$PROJECT" \
    -f compose.app.yaml \
    --env-file .env \
    up -d --wait --wait-timeout 180

echo "Running health checks..."

curl --fail --silent --show-error \
    "http://127.0.0.1:${FRONTEND_PORT}/" \
    >/dev/null

API_HEALTH="$(
    curl --fail --silent --show-error \
      "http://127.0.0.1:${BACKEND_PORT}/api/health"
)"

echo "$API_HEALTH"

echo "$API_HEALTH" | grep -q '"database":true'

echo "New slot healthy. Switching Apache..."

TMP="$(mktemp)"

cat >"$TMP" <<APACHE
<Proxy "balancer://pauvi-fe">
    BalancerMember "http://127.0.0.1:${FRONTEND_PORT}" retry=1
    BalancerMember "http://127.0.0.1:${OLD_FRONTEND_PORT}" retry=1 status=+H
    ProxySet lbmethod=byrequests
</Proxy>

<Proxy "balancer://pauvi-api">
    BalancerMember "http://127.0.0.1:${BACKEND_PORT}" retry=1
    BalancerMember "http://127.0.0.1:${OLD_BACKEND_PORT}" retry=1 status=+H
    ProxySet lbmethod=byrequests
</Proxy>
APACHE

BACKUP="${BALANCER_CONF}.bak"

if [[ -f "$BALANCER_CONF" ]]; then
    cp "$BALANCER_CONF" "$BACKUP"
fi

install -m 0644 "$TMP" "$BALANCER_CONF"
rm -f "$TMP"

if ! apache2ctl configtest; then
    echo "Apache config test failed. Rolling back."

    if [[ -f "$BACKUP" ]]; then
        cp "$BACKUP" "$BALANCER_CONF"
    fi

    exit 1
fi

apache2ctl graceful

echo "$TARGET" > "$ACTIVE_FILE"
echo "$REMOTE_COMMIT" > "$COMMIT_FILE"

echo "Deployment completed."
echo "Active slot: $TARGET"
echo "Commit: $REMOTE_COMMIT"
