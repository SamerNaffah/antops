# Antops migrations

This directory holds versioned schema changes. New installs run
`complete-schema.sql` once (which is the dump of the current state) and then
**stop here** — every file in this directory is already incorporated into the
baseline. Existing installs apply each new file in order.

## Layout

```
supabase/migrations/
  0001_security_hardening.sql   ← RLS, search_path, CHECK, indexes, triggers
  ...                           ← future migrations, numbered sequentially
```

Files are numbered `NNNN_short_description.sql`, four-digit zero-padded so they
sort lexicographically forever (until we hit migration #10000).

## Applying a migration

### Hosted Supabase

Open the SQL Editor in your project, paste the migration file, run it. Each
file is wrapped in a single `BEGIN`/`COMMIT` so it is all-or-nothing.

### Self-hosted (Docker compose)

```bash
docker compose exec -T postgres \
  psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  < supabase/migrations/0001_security_hardening.sql
```

Or, equivalently, with the bundled Makefile:

```bash
make migrate FILE=supabase/migrations/0001_security_hardening.sql
```

(Add a wrapper if you want — see open ticket in `ANTOPS_AUDIT.md`.)

## Authoring rules

1. **Idempotent.** Every migration must be safely re-runnable. Use
   `CREATE ... IF NOT EXISTS`, `DROP POLICY IF EXISTS` before `CREATE POLICY`,
   `ALTER FUNCTION ... SET ...` (which is itself idempotent), and `DO $$ ... $$`
   guards for anything that needs branching.
2. **Transactional.** Wrap the file in `BEGIN; ... COMMIT;`. Anything that
   cannot run inside a transaction (`CREATE INDEX CONCURRENTLY`, `VACUUM`,
   `REINDEX`) goes in its own file with a leading comment explaining why and
   how to apply it manually.
3. **No data backfills mixed with schema changes.** If a migration needs to
   move data, write it as two files: `NNNN_schema.sql` and
   `NNNN+1_backfill.sql`. Schema changes are fast and cheap to roll back;
   backfills are slow and rarely.
4. **Never edit a published migration.** Once a file is committed and tagged
   in a release, treat it as immutable. Fixes go in a follow-up migration.
5. **Mirror in `complete-schema.sql`.** After a migration is merged, regenerate
   (or manually edit) `complete-schema.sql` so fresh installs land in the same
   state as upgraded ones.

## CONCURRENT index creation

`CREATE INDEX IF NOT EXISTS ...` (without `CONCURRENTLY`) takes a write lock
on the table for the duration of the build. On a small install or a fresh DB
this is fine. On a hot production database with multi-million-row tables, run
each `CREATE INDEX` line manually with `CONCURRENTLY` (and outside the
transaction):

```sql
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_incidents_status
  ON public.incidents (status);
```

`CONCURRENTLY` does not work inside a transaction block, which is why the
migration file uses the locking variant by default.

## Why we keep `complete-schema.sql`

Two paths:

- **Fresh install.** Run `complete-schema.sql`. Skip migrations entirely.
- **Existing install.** Run each migration in order from the version you
  already have.

`complete-schema.sql` is the canonical "what does the schema look like right
now" dump. Migrations are the "how do we get there from before" record. Both
are committed.

This will eventually be replaced by the Supabase CLI's
`supabase db diff` / `supabase migration up` workflow. For now we keep the
process manual and explicit.
