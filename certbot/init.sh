#!/usr/bin/env bash
# Bootstraps a Let's Encrypt cert for one domain, via the standard
# nginx+certbot dummy-cert pattern. Run once per new service, from the
# hand_warmer repo root:
#
#   ./certbot/init.sh <domain> [--staging]
#
# Assumes:
#   - DNS for <domain> already points at this host
#   - `docker compose up -d nginx` has a matching conf.d/<service>.conf
#     already in place (its 80-only server block is enough for this to work)
set -euo pipefail
cd "$(dirname "$0")/.."

DOMAIN="${1:?Usage: ./certbot/init.sh <domain> [--staging]}"
EMAIL="${CERTBOT_EMAIL:-delarosasanovic@gmail.com}"
STAGING_FLAG=""
if [[ "${2:-}" == "--staging" ]]; then
  STAGING_FLAG="--staging"
  echo "Running in STAGING mode (avoids Let's Encrypt rate limits)."
fi

# Run a shell command inside a throwaway certbot container. Using
# `--entrypoint /bin/sh ... -c "..."` (rather than jamming a multi-command
# string into --entrypoint directly) so shell operators like && are
# actually interpreted as a shell would, instead of being passed as a
# literal argv token to whatever --entrypoint resolves to.
run_in_certbot() {
  docker compose run --rm --entrypoint /bin/sh certbot -c "$1"
}

if [ -d "certbot/conf/live/$DOMAIN" ] || [ -f "certbot/conf/renewal/$DOMAIN.conf" ]; then
  read -p "Existing certificate state found for $DOMAIN. Replace it? (y/N) " decision
  if [ "$decision" != "y" ] && [ "$decision" != "Y" ]; then
    exit 0
  fi
  echo "### Purging all existing cert state for $DOMAIN (including any numbered lineages) ..."
  run_in_certbot "rm -rf /etc/letsencrypt/live/${DOMAIN}* /etc/letsencrypt/archive/${DOMAIN}* /etc/letsencrypt/renewal/${DOMAIN}*.conf"
fi

echo "### Creating a dummy certificate for $DOMAIN so nginx can start ..."
mkdir -p "certbot/conf/live/$DOMAIN"
run_in_certbot "openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
  -keyout '/etc/letsencrypt/live/$DOMAIN/privkey.pem' \
  -out '/etc/letsencrypt/live/$DOMAIN/fullchain.pem' \
  -subj '/CN=localhost'"

echo "### Starting/reloading nginx with the dummy certificate ..."
docker compose up -d nginx
docker compose exec nginx nginx -s reload 2>/dev/null || true

echo "### Deleting dummy certificate ..."
run_in_certbot "rm -rf /etc/letsencrypt/live/$DOMAIN /etc/letsencrypt/archive/$DOMAIN /etc/letsencrypt/renewal/$DOMAIN.conf"

echo "### Requesting the real certificate from Let's Encrypt ..."
run_in_certbot "certbot certonly --webroot -w /var/www/certbot \
  $STAGING_FLAG \
  -d $DOMAIN \
  --email $EMAIL \
  --rsa-key-size 2048 \
  --agree-tos \
  --no-eff-email \
  --force-renewal \
  --cert-name $DOMAIN"

echo "### Reloading nginx ..."
docker compose exec nginx nginx -s reload

echo "Done. Certificate for $DOMAIN is live."
