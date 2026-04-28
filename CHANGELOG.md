# Changelog

All notable changes to Antops are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html) once
it leaves the early-stage `0.x` line.

## [Unreleased]

### Added
- `output: "standalone"` in `next.config.ts` so the Docker image actually
  builds from a fresh clone.
- `.env.selfhosted.example` matching `docker-compose.yml` 1:1.
- `Makefile` with `make up / down / logs / psql / migrate / health / clean`.
- `.dockerignore` for sane build contexts.
- `/api/health` route used by the compose `HEALTHCHECK`.
- Graceful SIGTERM/SIGINT shutdown in `server.js`, with env validation at
  boot.
- `supabase/migrations/0001_security_hardening.sql` — locks `search_path`
  on all 10 `SECURITY DEFINER` functions, enables RLS + policies on the 5
  previously-unprotected tables (`billing_integrations`, `team_invitations`,
  `incident_sequences`, `change_sequences`, `problem_sequences`), adds
  CHECK constraints on enum-like text columns, backfills 5 missing
  `updated_at` triggers, adds 15 indexes on hot filter / FK columns,
  tightens `team_invitations.organization_id` to `NOT NULL`. Idempotent.
- `docs/` tree with `README`, `self-hosting`, `architecture`, `database`,
  `api`, `comparison`, `deployment`, `integrations/pagerduty`, and
  `legal/{privacy,terms}`.
- `.github/` issue + PR templates and discussions/security advisory links.
- `CHANGELOG.md` (this file).

### Changed
- README rewritten around a three-command quickstart with no broken
  "coming soon" links.
- `docker-compose.yml` no longer publishes Postgres on port 5432 of the
  host (still reachable inside the bridge network; commented one-liner to
  re-enable for local debugging).
- All references to `github.com/antopshq/antops` corrected to
  `github.com/SamerNaffah/antops`.

### Removed
- Four unprotected `test` API routes under `src/app/api/{comments,itil,
  integrations/pagerduty,openai}/test/`.
- 9 internal-scaffolding docs from the open-sourcing process: `INDEX`,
  `IMPLEMENTATION_CHECKLIST`, `OPEN_SOURCE_SUMMARY`, `QUICK_REFERENCE`,
  `README.selfhosted`, `SELF_HOSTING_SUMMARY`, `SELF_HOSTING_MIGRATION_PLAN`,
  `RELEASE_READY`, `OPEN_SOURCE_CHECKLIST`, `DATABASE_SETUP`, `RESEND_SETUP`.

### Security
- 10 `SECURITY DEFINER` functions hardened against `search_path`-based
  privilege escalation.
- 5 multi-tenant tables that previously had RLS enabled but no policies
  (cross-tenant leak risk) now have org-scoped policies.

---

For changes prior to this audit, see `git log` — the commit history is the
source of truth before this changelog began.
