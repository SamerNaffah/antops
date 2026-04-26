# Antops

> Open-source ITIL platform — incidents, problems, changes, infrastructure mapping — built for teams that want ServiceNow-style coverage without the license.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Next.js](https://img.shields.io/badge/Next.js-15-black)](https://nextjs.org/)
[![TypeScript](https://img.shields.io/badge/TypeScript-5-blue)](https://www.typescriptlang.org/)
[![Status](https://img.shields.io/badge/status-early--stage-orange)]()

Antops is a modern, real-time IT operations platform. It ships the ITIL processes your on-call team actually uses (incident, problem, change management), a visual infrastructure graph, live collaboration, and optional AI-powered risk scoring.

> **Status.** Antops is early-stage OSS. It runs, but it is under active refactor — see [`../ANTOPS_AUDIT.md`](../ANTOPS_AUDIT.md) for the current punch list. Feedback and PRs welcome.

---

## Quickstart

You have two deployment paths. Pick one.

### A. Self-hosted (Docker) — recommended

Runs the whole stack on one host: Postgres, MinIO, Redis, and the app. No SaaS account required.

```bash
git clone https://github.com/SamerNaffah/antops.git
cd antops
cp .env.selfhosted.example .env
# edit .env and set strong passwords + NEXTAUTH_SECRET (openssl rand -base64 32)
make up
```

Then open <http://localhost:3000>.

Common commands (`make help` for the full list):

```
make up        # start the stack
make logs      # tail the app logs
make psql      # open a psql prompt against the app DB
make down      # stop (keeps data)
make clean     # stop AND wipe volumes (destroys data)
```

### B. Hosted Supabase (fastest for a dev workstation)

Uses a free Supabase project instead of local Postgres/storage. No Docker.

```bash
git clone https://github.com/SamerNaffah/antops.git
cd antops/antops-app
cp .env.example .env.local
# fill in NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY,
# SUPABASE_SERVICE_ROLE_KEY from your Supabase project's API settings
npm install
npm run dev
```

Then open <http://localhost:3000>. On first run, paste `complete-schema.sql` into Supabase's SQL Editor and run it once to create all tables and policies.

---

## What's inside

**Core ITIL**
- Incident management with full lifecycle (open → investigating → resolved → closed), priorities, assignment, SLA tracking
- Problem management: root-cause analysis, workarounds, known-error database, incident linking
- Change management: approval workflow, scheduling, rollback plans
- Infrastructure: visual topology with ReactFlow, drag-and-drop, dependency tracking

**Collaboration**
- Real-time comments over Socket.io
- `@mentions` and notifications
- File attachments

**Integrations**
- PagerDuty (incident ingest)
- Grafana (webhook alerts → incidents)
- REST API with API tokens

**AI (optional, bring your own key)**
- Risk scoring on infrastructure components
- Impact assessment from the dependency graph
- Incident-resolution suggestions

---

## Tech stack

Next.js 15 (App Router) • React 19 • TypeScript 5 • PostgreSQL (Supabase or self-hosted) • Socket.io • Tiptap editor • ReactFlow • Tailwind v4 • shadcn/ui (Radix) • OpenAI (optional).

For the deep architecture, see `docs/architecture.md` _(coming — see audit)_.

---

## Project layout

```
antops/
├── Dockerfile
├── docker-compose.yml
├── .env.selfhosted.example       # Docker path
├── Makefile                      # make up / down / logs / psql
├── docker/                       # Postgres init scripts
└── antops-app/                   # the Next.js application
    ├── .env.example              # hosted-Supabase path
    ├── package.json
    ├── next.config.ts
    ├── server.js                 # custom server (Next.js + Socket.io)
    ├── complete-schema.sql       # single-file DB schema (28 tables, RLS, triggers)
    ├── src/
    │   ├── app/                  # App Router pages + API routes
    │   ├── components/           # UI
    │   └── lib/                  # supabase clients, store, openai, websocket
    └── public/
```

---

## Configuration

Self-hosted mode (`.env.selfhosted.example`):

| Variable | Required | What it does |
|---|---|---|
| `POSTGRES_PASSWORD` | yes | App database password |
| `NEXTAUTH_SECRET` | yes | `openssl rand -base64 32` |
| `NEXTAUTH_URL` | yes | Public URL the app is served at |
| `MINIO_ROOT_PASSWORD` | yes | Object storage root password |
| `REDIS_PASSWORD` | yes | Cache / session store password |
| `OPENAI_API_KEY` | no | Enables AI features |
| `ANTHROPIC_API_KEY` | no | Alternative AI provider |

Supabase mode (`antops-app/.env.example`):

| Variable | Required | What it does |
|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | yes | Your Supabase project URL |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | yes | Public anon key |
| `SUPABASE_SERVICE_ROLE_KEY` | yes | Server-only secret |
| `NEXT_PUBLIC_APP_URL` | yes | Public URL |
| `OPENAI_API_KEY` | no | Enables AI features |

---

## Contributing

PRs welcome — see [`CONTRIBUTING.md`](CONTRIBUTING.md). For anything non-trivial, open an issue first.

Bug reports and feature requests: <https://github.com/SamerNaffah/antops/issues>

---

## Security

See [`SECURITY.md`](SECURITY.md) for reporting vulnerabilities. **Do not** file security issues on the public tracker.

A known-issues list (with severity + planned fixes) lives in `ANTOPS_AUDIT.md` at the repo root.

---

## License

MIT — see [`LICENSE`](LICENSE).
