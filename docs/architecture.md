# Architecture

A short tour of how the moving parts fit together. Detail beyond what's
strictly useful is deliberately omitted; if you need more, the source is the
source of truth.

## High-level

```
            ┌────────────────────────────┐
            │  Browser                   │
            │  (Next.js client + WS)     │
            └────────────┬───────────────┘
                         │ HTTP + WS
                         ▼
            ┌────────────────────────────┐
            │  server.js                 │
            │  (custom Next.js server)   │
            │  ─ HTTP handler            │
            │  ─ Socket.io               │
            └─────┬──────────────┬───────┘
                  │              │
                  ▼              ▼
        ┌────────────────┐  ┌──────────────────┐
        │  Next.js API   │  │  Socket.io rooms │
        │  routes        │  │  (per-user)      │
        └─────┬──────────┘  └─────────┬────────┘
              │                       │
              ▼                       ▼
        ┌─────────────────────────────────────┐
        │  Supabase / Postgres                │
        │  (28 tables, RLS, triggers,         │
        │   SECURITY DEFINER helpers)         │
        └─────────────────────────────────────┘
              │
              ▼
        ┌────────────────┐
        │  Object store  │
        │  (Supabase     │
        │   Storage or   │
        │   MinIO)       │
        └────────────────┘
              │
              ▼
        ┌────────────────┐   ┌────────────────┐
        │  OpenAI        │   │  PagerDuty /   │
        │  (optional)    │   │  Grafana       │
        └────────────────┘   └────────────────┘
```

## Components

### `server.js` — the custom server

A thin wrapper around `next.js` that:
1. Validates required env vars at boot, fails fast if any are missing.
2. Starts the Next.js HTTP handler.
3. Attaches Socket.io to the same HTTP server (best-effort — failure
   downgrades to a non-real-time experience).
4. Handles SIGTERM/SIGINT by draining connections then exiting.

Why custom: Socket.io needs a real HTTP server to upgrade connections,
which `next start` does not expose. One process, one port.

### `src/app/` — App Router routes + API

Route groups follow ITIL: `incidents/`, `problems/`, `changes/`,
`infrastructure/`. API routes live under `src/app/api/<resource>/route.ts`.
Common patterns:

- Auth check via `createSupabaseServerClient()` from `src/lib/supabase/server.ts`.
- Org scoping comes from RLS — most queries don't filter `organization_id`
  in code, they let the policy do it.

### `src/lib/`

| File | Job |
|---|---|
| `supabase/server.ts`, `supabase/client.ts` | Configured Supabase clients |
| `store.ts` | Data access layer (~419 lines, slated for replacement — see audit §3.3) |
| `openai-client.ts` | OpenAI singleton + retry policy |
| `websocket-server.ts` | Socket.io setup, auth handshake, broadcast helpers |

### `src/components/`

shadcn/ui under `components/ui/`, feature-specific components everywhere
else. The big one is `InfrastructureView.tsx` (3K+ lines) which renders the
ReactFlow canvas — slated for breakup per audit §3.4.

### Database (`complete-schema.sql`)

28 tables, rough domains:
- ITIL: `incidents`, `problems`, `changes`, plus `*_sequences` counters
- Infrastructure: `infrastructure_nodes`, `infrastructure_edges`,
  `infrastructure_zones`, `infrastructure_environments`
- Collab: `comments`, `notifications`, `comment_notifications`
- AI: `ai_cache`, `ai_scan_tokens`, `openai_usage_logs`
- Auth/billing: `profiles`, `organizations`, `organization_memberships`,
  `team_invitations`, `billing_integrations`
- Integrations: `pagerduty_integrations`, `grafana_integrations`,
  `api_tokens`, `slo_configurations`

RLS is enabled on every table; policies gate by `organization_id` against
`get_user_organization_id()`. Helper functions are `SECURITY DEFINER` with
a locked `search_path = public, pg_temp` (see migration `0001_security_hardening.sql`).

## Request flow — incident creation

1. Client `POST /api/incidents` with the form payload.
2. `route.ts` validates the payload, gets the auth context.
3. `INSERT INTO incidents` — RLS policy allows the row because
   `auth.uid() = created_by` and `organization_id =
   get_user_organization_id()`.
4. `BEFORE INSERT` trigger `handle_incident_before_insert` calls
   `generate_incident_number()` which UPSERTs into `incident_sequences` to
   produce a per-org running number (`INC-2026-0042` style).
5. After the insert, the API route emits a Socket.io broadcast to the org's
   room so other tabs/clients update live.

## Persistence options

| | Hosted Supabase | Self-hosted (Docker) |
|---|---|---|
| Database | Supabase Postgres | Local Postgres 16 |
| Auth | Supabase Auth | NextAuth (planned) |
| Storage | Supabase Storage | MinIO |
| Schema | `complete-schema.sql` | `docker/postgres/schema.sql` |
| Status | works | alpha — see audit §3.2 |

Both paths are documented in `self-hosting.md` and `deployment.md`. Picking
one and consolidating is the largest open architectural decision in the
project today.

## What's not in this diagram (yet)

- A Redis-backed session store and Socket.io adapter for horizontal scale —
  audit §3.5.
- A real `audit_log` table for compliance — audit §3.7.
- An attachments table that replaces the JSONB blobs on incidents/changes/problems —
  audit §3.6.

These are tracked in `ANTOPS_AUDIT.md`.
