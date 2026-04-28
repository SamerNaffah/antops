# Self-hosting Antops

This is the Docker Compose path: Postgres + MinIO + Redis + the app, all on
a single host, no SaaS account needed. For the hosted-Supabase path, see
[`deployment.md`](deployment.md).

> **Heads-up.** The self-hosted path uses a hand-rolled schema in
> `docker/postgres/schema.sql` and a NextAuth-style auth flow. The app's
> source code currently still imports `@supabase/supabase-js` and assumes a
> Supabase-shaped data layer. Until that ambiguity is resolved (tracked in
> `ANTOPS_AUDIT.md` §3.2), treat self-hosted as **alpha** — it stands up but
> some features may misbehave. The hosted-Supabase path is more stable today.

## Requirements

| | Minimum | Recommended |
|---|---|---|
| CPU | 2 cores | 4+ cores |
| RAM | 4 GB | 8 GB+ |
| Disk | 20 GB SSD | 50 GB SSD |
| Docker | Engine 24+ | latest |
| Docker Compose | v2 | latest |
| OS | Linux / macOS / Windows + WSL2 | Linux (Ubuntu 22.04 LTS) |

## Quickstart

```bash
git clone https://github.com/SamerNaffah/antops.git
cd antops

cp .env.selfhosted.example .env
# Edit .env and set strong values for:
#   POSTGRES_PASSWORD
#   NEXTAUTH_SECRET     (openssl rand -base64 32)
#   MINIO_ROOT_PASSWORD
#   REDIS_PASSWORD

make up
```

Open <http://localhost:3000>. First boot takes ~60 seconds while images pull
and the schema seeds.

## What `make up` actually does

- Builds the app image from the `Dockerfile` in this directory (multi-stage,
  outputs Next.js standalone, runs as non-root).
- Starts five services on the `antops-network` bridge:
  - `postgres` — runs `docker/postgres/init.sql` and `docker/postgres/schema.sql`
    on first boot, persisted to the `postgres_data` volume.
  - `minio` — S3-compatible object storage on ports 9000 (S3) and 9001 (web
    console). Persisted to `minio_data`.
  - `minio-init` — one-shot container that creates the `antops-files` bucket.
  - `redis` — session/cache store, persisted to `redis_data`.
  - `app` — the Next.js application on port 3000. Probes
    `/api/health` for liveness.

Postgres is reachable only on the bridge network — port 5432 is not exposed
to the host by default. If you need to connect a local `psql` for debugging,
uncomment the `127.0.0.1:5432:5432` line in `docker-compose.yml` or use
`make psql`.

## Make targets

```
make help      # list all targets
make up        # build + start the stack
make down      # stop, keep data
make restart   # restart the app container
make logs      # tail app logs
make ps        # show container status
make shell     # shell into the app container
make psql      # psql prompt against the app DB
make migrate   # (re)apply complete-schema.sql — destructive
make health    # curl /api/health
make clean     # stop AND wipe all volumes (destroys data)
```

## Environment variables

`make up` will refuse to start if `.env` is missing. The full reference is in
`.env.selfhosted.example` — the variables that matter:

| Variable | Required | Notes |
|---|---|---|
| `POSTGRES_PASSWORD` | yes | Strong random string. |
| `POSTGRES_USER` | no | Defaults to `antops`. |
| `POSTGRES_DB` | no | Defaults to `antops`. |
| `NEXTAUTH_URL` | yes | The public URL the app is served on. |
| `NEXTAUTH_SECRET` | yes | `openssl rand -base64 32`. |
| `MINIO_ROOT_USER` | no | Defaults to `antops`. |
| `MINIO_ROOT_PASSWORD` | yes | Strong random string. |
| `REDIS_PASSWORD` | yes | Strong random string. |
| `OPENAI_API_KEY` | no | Enables AI features. |
| `ANTHROPIC_API_KEY` | no | Alternative AI provider. |
| `ENABLE_AI_FEATURES` | no | `true` / `false`, default `true`. |
| `ENABLE_INTEGRATIONS` | no | `true` / `false`, default `true`. |

## Behind a reverse proxy (TLS)

The bundled compose file ships an Nginx service definition that's commented
out by default. Uncomment it and drop a config + cert into `docker/nginx/`,
or — easier — put the app behind your existing Caddy / Traefik / nginx and
point it at `localhost:3000`. Set `NEXTAUTH_URL` to the public HTTPS URL.

## Backup

```bash
# Postgres
docker compose exec -T postgres pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" \
  | gzip > "antops-$(date +%F).sql.gz"

# MinIO (file attachments)
docker compose exec minio mc mirror /data /backup
# …or `docker run --rm -v antops_minio_data:/data alpine tar czf - /data > minio-$(date +%F).tar.gz`
```

## Upgrades

```bash
git pull
make build
docker compose up -d
```

If a release adds a new SQL migration, apply it manually after the upgrade
(see `supabase/migrations/README.md`):

```bash
docker compose exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  < supabase/migrations/0001_security_hardening.sql
```

## Troubleshooting

**`make up` errors with "Missing env var".** You forgot to `cp
.env.selfhosted.example .env` or to fill in the required passwords.

**App container restarts in a loop.** `docker compose logs app` will show
why. Most common causes:
- Postgres still seeding on first boot — wait 30 seconds.
- `NEXTAUTH_URL` doesn't match the URL you're hitting (causes auth callbacks
  to fail).
- Schema seed failed because `docker/postgres/schema.sql` and
  `complete-schema.sql` drifted — run `make clean && make up` to recreate the
  volume.

**WebSocket / real-time comments don't update.** Check the app logs for
`websocket server failed to init`. The custom server falls back to plain
Next.js if Socket.io can't bind, so the rest of the app keeps working — but
real-time features are silently disabled.

**File uploads fail.** Visit <http://localhost:9001>, log in with
`MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD`, confirm the `antops-files` bucket
exists. If not, the `minio-init` container failed — `docker compose logs
minio-init` will tell you why.

**Postgres healthcheck never goes green.** Almost always wrong password.
`docker compose exec postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"` —
if that prompts for a password, your env is mismatched.

## Known limitations of self-hosted today

These are documented in `ANTOPS_AUDIT.md`:

- **Schema drift.** `docker/postgres/schema.sql` (NextAuth-style) and
  `complete-schema.sql` (Supabase-style) diverge. The repo's app code targets
  the latter. The maintainer is choosing one path — see the audit's §3.2.
- **Storage code path.** The app currently writes attachments via Supabase
  Storage; the MinIO bucket is provisioned but isn't the active storage
  backend until the data layer is reworked.
- **Single-node only.** No story for multi-replica app, shared Redis adapter,
  or external Postgres yet.

For the latest status of these items, see the punch list in `ANTOPS_AUDIT.md`.
