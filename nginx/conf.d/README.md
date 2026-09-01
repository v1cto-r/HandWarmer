# Adding a new service

Every `*.conf` file in this directory is auto-loaded by `nginx.conf`
(`include /etc/nginx/conf.d/*.conf`) — no other file needs editing.

1. Copy this template to `<service>.conf`.
2. Replace `SERVICE_DOMAIN`, `SERVICE_BACKEND` and `SERVICE_FRONTEND`.
   `SERVICE_BACKEND`/`SERVICE_FRONTEND` must match the `container_name:`
   values in that app's own `docker-compose.yml`, and that compose file
   must attach those containers to the shared `edge` network (see the
   top-level README for the full pattern).
3. Bootstrap its TLS cert: `./certbot/init.sh SERVICE_DOMAIN` (DNS must
   already point at this host, and nginx must already be running so it
   can serve the ACME HTTP-01 challenge).
4. `docker compose restart nginx` (or just `docker compose up -d`, it's
   already watching this mounted directory on the next reload).

```nginx
server {
  listen 80;
  server_name SERVICE_DOMAIN;

  location /.well-known/acme-challenge/ {
    root /var/www/certbot;
  }

  location / {
    return 301 https://$host$request_uri;
  }
}

server {
  listen 443 ssl;
  http2 on;
  server_name SERVICE_DOMAIN;

  ssl_certificate /etc/letsencrypt/live/SERVICE_DOMAIN/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/SERVICE_DOMAIN/privkey.pem;
  ssl_protocols TLSv1.2 TLSv1.3;

  location /api/ {
    proxy_pass http://SERVICE_BACKEND:8000/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
  }

  location / {
    proxy_pass http://SERVICE_FRONTEND:3000;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
  }
}
```
