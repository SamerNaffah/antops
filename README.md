# Antops

> Open-source ITIL platform — incidents, problems, changes, infrastructure mapping — built for teams that want ServiceNow-style coverage without the license.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Next.js](https://img.shields.io/badge/Next.js-15-black)](https://nextjs.org/)
[![TypeScript](https://img.shields.io/badge/TypeScript-5-blue)](https://www.typescriptlang.org/)
[![Status](https://img.shields.io/badge/status-early--stage-orange)]()

Antops is a modern, real-time IT operations platform. It ships the ITIL processes your on-call team actually uses (incident, problem, change management), a visual infrastructure graph, live collaboration, and optional AI-powered risk scoring.

> **Status.** Antops is early-stage OSS. It runs, but it is under active refactor — see [`ANTOPS_AUDIT.md`](ANTOPS_AUDIT.md) for the current punch list. Feedback and PRs welcome.

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

Then open <http://localhost:3000>. Full guide: [`docs/self-hosting.md`](docs/self-hosting.md).

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
cd antops
cp .env.example .env.local
# fill in NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY,
# SUPABASE_SERVICE_ROLE_KEY from your Supabase project's API settings
npm install
npm run dev
```

Then open <http://localhost:3000>. On first run, paste `complete-schema.sql` into Supabase's SQL Editor and run it once to create all tables and policies. Full guide: [`docs/deployment.md`](docs/deployment.md).

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

Next.js 15 (App Router) • React 19 • TypeScript 5 • PostgreSQL (Supabase or self-hosted) • Socket.io • Tiptap editor • ReactFlow • Tailwind v4 • shadcn/ui (Radix) • OpenAI (optional). The deeper tour: [`docs/architecture.md`](docs/architecture.md).

---

## Project layout

```
antops/
├── README.md
├── LICENSE                       MIT
├── TRADEMARK.md                  ANTOPS name + logo policy
├── CONTRIBUTING.md
├── CODE_OF_CONDUCT.md
├── SECURITY.md                   how to report vulns
├── CHANGELOG.md
├── ANTOPS_AUDIT.md               current punch list
│
├── Dockerfile                    multi-stage, non-root, healthcheck
├── docker-compose.yml            postgres + minio + redis + app
├── Makefile                      make up / down / logs / psql / clean
├── .dockerignore
├── .env.example                  hosted-Supabase mode
├── .env.selfhosted.example       Docker / self-hosted mode
│
├── complete-schema.sql           single-file DB schema (28 tables, RLS, triggers)
├── server.js                     custom Next.js server (HTTP + Socket.io)
│
├── docker/                       Postgres init scripts
├── supabase/migrations/          versioned SQL changes
├── docs/
│   ├── README.md                 doc index
│   ├── self-hosting.md
│   ├── deployment.md
│   ├── architecture.md
│   ├── database.md
│   ├── api.md
│   ├── comparison.md
│   ├── integrations/
│   └── legal/
└── src/
    ├── app/                      App Router pages + API routes
    ├── components/               UI
    └── lib/                      supabase clients, store, openai, websocket
```

---

## Configuration

Self-hosted (`.env.selfhosted.example`):

| Variable | Required | What it does |
|---|---|---|
| `POSTGRES_PASSWORD` | yes | App database password |
| `NEXTAUTH_SECRET` | yes | `openssl rand -base64 32` |
| `NEXTAUTH_URL` | yes | Public URL the app is served at |
| `MINIO_ROOT_PASSWORD` | yes | Object storage root password |
| `REDIS_PASSWORD` | yes | Cache / session store password |
| `OPENAI_API_KEY` | no | Enables AI features |
| `ANTHROPIC_API_KEY` | no | Alternative AI provider |

Supabase (`.env.example`):

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

Bug reports and feature requests: <https://github.com/SamerNaffah/antops/issues>. Questions and ideas: [Discussions](https://github.com/SamerNaffah/antops/discussions).

---

## Security

See [`SECURITY.md`](SECURITY.md) for reporting vulnerabilities. **Do not** file security issues on the public tracker — use [GitHub Security Advisories](https://github.com/SamerNaffah/antops/security/advisories/new).

A known-issues list (with severity + planned fixes) lives in [`ANTOPS_AUDIT.md`](ANTOPS_AUDIT.md).

---

## License

MIT — see [`LICENSE`](LICENSE). Note the trademark carve-out in [`TRADEMARK.md`](TRADEMARK.md): the code is yours under MIT; the ANTOPS name and logo are not.
