#!/usr/bin/env bash
set -euo pipefail

REPO="/home/paulius/pauvi"
REPO_URL="https://github.com/paulius-bulotas/pauvi.git"
BRANCH="main"
LOCK="/run/lock/pauvi-deploy.lock"

exec 9>"$LOCK"
flock -n 9 || exit 0

if [ ! -d "$REPO/.git" ]; then
  runuser -u paulius -- git clone --branch "$BRANCH" "$REPO_URL" "$REPO"
  changed=1
else
  before="$(runuser -u paulius -- git -C "$REPO" rev-parse HEAD)"
  runuser -u paulius -- git -C "$REPO" fetch --prune origin "$BRANCH"
  after="$(runuser -u paulius -- git -C "$REPO" rev-parse "origin/$BRANCH")"

  if [ "$before" != "$after" ]; then
    runuser -u paulius -- git -C "$REPO" reset --hard "$after"
    changed=1
  else
    changed=0
  fi
fi

cd "$REPO"

if [ ! -f .env ]; then
  echo "ERROR: $REPO/.env missing. Copy .env.example to .env and set secrets." >&2
  exit 1
fi

frontend_running="$(docker compose ps --status running -q frontend 2>/dev/null || true)"
backend_running="$(docker compose ps --status running -q backend 2>/dev/null || true)"
mysql_running="$(docker compose ps --status running -q mysql 2>/dev/null || true)"

if [ "$changed" -eq 0 ] && [ -n "$frontend_running" ] && [ -n "$backend_running" ] && [ -n "$mysql_running" ]; then
  echo "No Git changes; stack is already running."
  exit 0
fi

docker compose config >/dev/null
docker compose build --pull
docker compose up -d --remove-orphans

docker compose ps
