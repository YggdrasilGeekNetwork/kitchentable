# Deploying to a DigitalOcean droplet

Production is a single droplet running the app, Postgres and Redis, deployed with
[Kamal](https://kamal-deploy.org) **from GitHub Actions** — nothing deploys from a dev
machine. Every push to `master` runs CI and, if it passes, deploys.

The deploy is idempotent: the same workflow sets up a brand-new droplet or updates a
running one, so there is no separate "first deploy".

## What runs where

| Where | What |
|---|---|
| GitHub runner | CI (RuboCop, Brakeman, tests), building the image, pushing it to `ghcr.io/<owner>/<repo>`, running Kamal over SSH |
| Droplet | `kamal-proxy` (ports 80/443, zero-downtime switches, health check on `/up`), the app (Rails + Thruster, Solid Queue worker inside Puma), Postgres 16 and Redis 7 |

Postgres and Redis publish no ports: they're only reachable on Kamal's private Docker
network. Their data lives on the droplet in `/root/kitchentable-db/data` and
`/root/kitchentable-redis/data`.

## One-time setup

### 1. Create the droplet

- **Image:** Ubuntu 24.04 LTS (x64).
- **Size:** 2 GB RAM recommended (1 GB works — the bootstrap adds 2 GB of swap).
- **Authentication:** an SSH key used only for deploys:

  ```bash
  ssh-keygen -t ed25519 -f kitchentable_deploy -N "" -C "kitchentable deploy"
  ```

  Add `kitchentable_deploy.pub` to the droplet when creating it (DigitalOcean →
  *Settings → Security → SSH keys*). The private key goes to GitHub (below).

With [`doctl`](https://docs.digitalocean.com/reference/doctl/) instead of the dashboard:

```bash
doctl compute ssh-key import kitchentable-deploy --public-key-file kitchentable_deploy.pub
doctl compute droplet create kitchentable --image ubuntu-24-04-x64 --size s-1vcpu-2gb \
  --region nyc3 --ssh-keys "$(doctl compute ssh-key list --format ID --no-header | head -1)"
```

### 2. Point the domain at it (optional)

For HTTPS, add an **A record** for the domain (e.g. `kitchentable.yg.net.br`) pointing at
the droplet's IP. Without a domain the app is served over plain HTTP on the IP — note
that browsers only allow camera/microphone access (planned A/V) over HTTPS.

### 3. Configure the GitHub repository

Use a **`production` environment** (*Settings → Environments → New environment*, named
exactly `production`, as in the workflow) and put the values below in its
*Environment secrets* / *Environment variables*. Only the deploy job can read them —
CI on pull requests can't — and under *Deployment branches and tags* you can restrict
deploys to `master` (and optionally require a reviewer to approve each deploy).
Repository-level secrets/variables also work, without those protections.

| Kind | Name | Value |
|---|---|---|
| Variable | `DROPLET_IP` | The droplet's public IPv4 |
| Variable | `APP_DOMAIN` | *(optional)* e.g. `kitchentable.yg.net.br` — enables HTTPS via Let's Encrypt |
| Secret | `DROPLET_SSH_KEY` | Contents of the private key `kitchentable_deploy` |
| Secret | `SECRET_KEY_BASE` | Output of `bin/rails secret` |
| Secret | `POSTGRES_PASSWORD` | Output of `openssl rand -hex 32` (keep it URL-safe) |

The registry login uses the workflow's own `GITHUB_TOKEN`; nothing to configure.

### 4. Deploy

Push to `master`, or run **Actions → Deploy → Run workflow**. The first run takes a few
minutes longer (Docker install, Postgres/Redis boot, certificate issuance). On a new
database the first boot also queues the Scryfall card catalog sync, which takes about a
minute to fill the catalog.

## What every deploy does

1. **CI** — the deploy only continues if lint, security scan and tests pass.
2. **Checks** — required variables/secrets are present; with `APP_DOMAIN`, that its DNS
   already points at the droplet (Let's Encrypt needs it).
3. **`bin/bootstrap-droplet`** over SSH — each step checks before acting: 2 GB swap,
   firewall (SSH, 80, 443 only), automatic security updates, fail2ban, Docker, and
   restarting a stopped Postgres/Redis container.
4. **`kamal setup`** — installs Docker if missing, boots Postgres/Redis/kamal-proxy if
   they don't exist yet (existing ones are left alone), builds and pushes the image,
   starts the new app container, waits for `/up`, switches traffic, removes the old one.
5. **On app boot** (`bin/docker-entrypoint`) — creates the database if needed, loads
   the Solid Cache/Queue tables only if missing (so queued jobs survive deploys), runs
   migrations, and queues the catalog sync only while the catalog is empty.

## Operating it

From your machine, over SSH (`ssh -i kitchentable_deploy root@<ip>`):

```bash
docker ps                                                     # what's running
docker logs -f $(docker ps -q --filter label=service=kitchentable --filter label=role=web)
docker exec -it $(docker ps -q --filter label=service=kitchentable --filter label=role=web) bin/rails console
docker exec -it kitchentable-db psql -U kitchentable kitchentable_production
```

- **A deploy was interrupted and the next one says a deploy lock exists:** run
  **Actions → Deploy → Run workflow** with *Release a stale deploy lock* checked.
- **Rolling back:** revert the commit on `master`; the deploy ships the previous code.
- **Backups:** not automated yet — enable DigitalOcean droplet backups, or schedule a
  `pg_dump` of `kitchentable-db`.

## Caveats

- `POSTGRES_PASSWORD` is applied when Postgres first initializes its data directory.
  Changing the secret later doesn't change the database user's password: run
  `ALTER USER kitchentable PASSWORD '...'` in `psql` first, then update the secret.
- The image is pushed to GHCR as a private package. Deploys log the droplet into GHCR
  with the workflow's short-lived token; manual `docker pull`s on the droplet need a
  personal access token with `read:packages`.
