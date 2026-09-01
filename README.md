# hand_warmer

Shared nginx + certbot reverse-proxy layer for a single EC2 host running
multiple small personal app stacks (each its own repo, its own
`docker-compose.yml` for backend+frontend only). This repo owns:

- the one nginx container bound to host ports 80/443
- the one certbot container renewing every domain's cert
- the shared `edge` Docker network that app repos attach to

No app-specific containers live here — just routing config. Each app
stack (e.g. `whereami`) is a sibling directory with its own repo/compose
file that plugs into this one.

```
Internet -> nginx (this repo, TLS termination, one per host)
              |-- whereami.14082006.xyz -> whereami-backend / whereami-frontend
              '-- <next-app>.example.com -> <next-app>-backend / <next-app>-frontend

nginx + certbot <-> shared "edge" Docker network <-> each app's containers
```

## One-time host setup (new EC2 instance)

A fresh instance has no git yet, so install it first (`bootstrap-host.sh`
handles everything else, but you need git just to clone this repo):

```bash
sudo dnf install -y git
git clone <hand_warmer-repo-url> hand_warmer
cd hand_warmer
./scripts/bootstrap-host.sh
sudo tailscale up   # open the printed URL, approve the device in your tailnet admin
# log out/in (or `newgrp docker`) so your user can run docker without sudo
```

`bootstrap-host.sh` opens an interactive checkbox menu (all items start
checked) — arrow keys to move, space to toggle, enter to run the selected
steps, `q` to abort without installing anything. Re-running it later is
safe (every step is idempotent), so uncheck everything except what
changed if you just need to redo one piece.

Also open inbound TCP 80/443 (0.0.0.0/0) on this instance's Security
Group — nginx needs both for ACME challenges and normal traffic.

## Bring up the shared proxy layer

```bash
docker compose up -d
docker network ls | grep edge     # sanity check: edge network exists
docker compose ps                 # nginx + certbot both running
```

At this point nginx is up but will fail to serve any app's HTTPS block
until that app's real cert exists — that's expected, `init.sh` (next
step) handles it per domain.

## Add a service (first time, e.g. `whereami`)

1. Point the service's domain's DNS A/AAAA record at this host's IP.
2. Clone the app repo as a sibling of `hand_warmer`, e.g.:
   ```bash
   cd ..
   git clone <whereami-repo-url> whereami
   cd whereami
   cp .env.example .env   # fill in real values per that repo's own README
   ```
3. Confirm the app's `docker-compose.yml` gives its containers stable
   `container_name:` values and attaches them to the external `edge`
   network (already true for `whereami` — see its compose file).
4. Confirm `hand_warmer/nginx/conf.d/` has a `<service>.conf` pointing at
   those container names (see `nginx/conf.d/README.md` for the template;
   `whereami.conf` already exists here as the reference example).
5. Bootstrap its cert — nginx must already be running (previous section):
   ```bash
   cd ../hand_warmer
   ./certbot/init.sh whereami.14082006.xyz
   # add --staging on a first dry run if you want to avoid burning
   # Let's Encrypt's real rate limit while testing
   ```
6. Start the app itself:
   ```bash
   cd ../whereami
   docker compose up -d --build
   ```
7. Verify: `curl -I https://whereami.14082006.xyz` returns a real TLS
   response (not a connection error or the dummy cert), and the app works
   end-to-end in a browser.

## Add another service later

Same as steps 1–7 above, just with a new domain, new sibling repo, and a
new `hand_warmer/nginx/conf.d/<service>.conf` (copy the template in
`nginx/conf.d/README.md`). Nothing in this repo's `docker-compose.yml` or
`nginx.conf` needs to change — conf.d files are auto-loaded, and the one
certbot container renews every domain's cert automatically.

## Renewals

Handled automatically — the `certbot` service here loops `certbot renew`
every 12h and covers every domain under `certbot/conf`, regardless of how
many services have been added. Nothing to run manually after `init.sh`.
