# Pauvi Docker production setup

## Architecture

Internet/LAN -> host Apache :80 -> 127.0.0.1:8081 -> frontend Apache container
                                                \-> /api -> backend:3000 -> mysql:3306

SeaFile remains on its own host Apache vhost and is not affected.

## Local development

1. Copy env examples:
   cp FE/.env.example FE/.env
   cp BE/.env.example BE/.env
2. Start MySQL only:
   cp .env.example .env
   edit .env and set passwords
   docker compose up -d mysql
3. At repo root:
   npm install
   npm run dev
4. Production-like local build check:
   npm run build

FE uses /api. Vite dev proxies /api to the backend on 127.0.0.1:3000.

## Server first deploy

1. Copy repo to /home/paulius/pauvi (or let deploy-server.sh clone it).
2. cp .env.example .env and replace all CHANGE_ME values.
3. mkdir -p /srv/pauvi-data/pauvi/mysql
4. docker compose config
5. docker compose build --pull
6. docker compose up -d
7. curl http://127.0.0.1:8081/api/health

## Host Apache

Enable modules:
  a2enmod proxy proxy_http headers

Install deploy/apache/pauvi.conf as /etc/apache2/sites-available/pauvi.conf,
enable it, configtest, reload Apache.

## Auto deploy every 15 minutes

Install:
  cp scripts/deploy-server.sh /usr/local/bin/pauvi-deploy
  chmod 755 /usr/local/bin/pauvi-deploy
  cp deploy/systemd/pauvi-deploy.service /etc/systemd/system/
  cp deploy/systemd/pauvi-deploy.timer /etc/systemd/system/
  systemctl daemon-reload
  systemctl enable --now pauvi-deploy.timer

Manual run:
  systemctl start pauvi-deploy.service
  journalctl -u pauvi-deploy.service -n 100 --no-pager
  systemctl list-timers --all | grep pauvi-deploy
