-- ============================================================================
-- 0001_security_hardening.sql
--
-- Closes the security and integrity gaps surfaced in ANTOPS_AUDIT.md §1.5,
-- §1.6, §2.10, §2.11, §2.12.
--
-- This migration is fully idempotent — running it twice is safe.
--
-- Apply on existing installs:
--   psql "$DATABASE_URL" -f supabase/migrations/0001_security_hardening.sql
-- Or via Supabase SQL Editor: paste the file and run.
--
-- Fresh installs already get all of this baked into complete-schema.sql.
--
-- Sections:
--   1. Lock search_path on all SECURITY DEFINER functions     (§1.6)
--   2. Enable RLS + policies on the 5 unprotected tables       (§1.5)
--   3. CHECK constraints on enum-like text columns             (§2.10)
--   4. Backfill missing updated_at triggers                     (§2.11)
--   5. Indexes on hot filter columns                            (§2.12)
--   6. Tighten team_invitations.organization_id (NOT NULL)     (§1.5 detail)
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. SECURITY DEFINER functions — lock search_path
-- ----------------------------------------------------------------------------
-- A SECURITY DEFINER function runs with the privileges of its owner. Without
-- a fixed search_path, an attacker can shadow built-in objects (e.g. by
-- creating a malicious `public.now()`) and hijack execution. Pinning the
-- search_path to `public, pg_temp` neutralises that vector.
--
-- ALTER FUNCTION ... SET is idempotent — re-running just rewrites the value.
-- ----------------------------------------------------------------------------

ALTER FUNCTION public.check_ai_scan_tokens(uuid, integer)            SET search_path = public, pg_temp;
ALTER FUNCTION public.check_and_update_billing_tiers()               SET search_path = public, pg_temp;
ALTER FUNCTION public.clean_expired_ai_cache()                       SET search_path = public, pg_temp;
ALTER FUNCTION public.consume_ai_scan_tokens(uuid, integer)          SET search_path = public, pg_temp;
ALTER FUNCTION public.get_user_ai_scan_status(uuid)                  SET search_path = public, pg_temp;
ALTER FUNCTION public.get_user_organization_id()                     SET search_path = public, pg_temp;
ALTER FUNCTION public.handle_new_user()                              SET search_path = public, pg_temp;
ALTER FUNCTION public.set_billing_expiration()                       SET search_path = public, pg_temp;
ALTER FUNCTION public.update_cache_access(uuid)                      SET search_path = public, pg_temp;
ALTER FUNCTION public.user_has_org_access(uuid)                      SET search_path = public, pg_temp;


-- ----------------------------------------------------------------------------
-- 2. RLS — enable + policies on the 5 unprotected tables
-- ----------------------------------------------------------------------------
-- Mirror the pattern already used for incidents/problems/changes:
--   * SELECT — visible to org members.
--   * INSERT / UPDATE / DELETE — gated on org membership and (where it makes
--     sense) on `owner`/`admin` role via organization_memberships.
--
-- The sequence tables (incident_/change_/problem_sequences) are hot paths:
-- the BEFORE INSERT triggers on incidents/changes/problems UPSERT into them
-- as the calling user. We therefore allow plain org-membership writes —
-- no admin gating, or every insert breaks.
-- ----------------------------------------------------------------------------

-- 2a. team_invitations -------------------------------------------------------

ALTER TABLE public.team_invitations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Org members can view invitations" ON public.team_invitations;
CREATE POLICY "Org members can view invitations"
  ON public.team_invitations FOR SELECT
  USING (organization_id = public.get_user_organization_id());

DROP POLICY IF EXISTS "Org admins can create invitations" ON public.team_invitations;
CREATE POLICY "Org admins can create invitations"
  ON public.team_invitations FOR INSERT
  WITH CHECK (
    organization_id = public.get_user_organization_id()
    AND EXISTS (
      SELECT 1 FROM public.organization_memberships m
      WHERE m.user_id = auth.uid()
        AND m.organization_id = team_invitations.organization_id
        AND m.role IN ('owner', 'admin')
    )
  );

DROP POLICY IF EXISTS "Org admins can update invitations" ON public.team_invitations;
CREATE POLICY "Org admins can update invitations"
  ON public.team_invitations FOR UPDATE
  USING (
    organization_id = public.get_user_organization_id()
    AND EXISTS (
      SELECT 1 FROM public.organization_memberships m
      WHERE m.user_id = auth.uid()
        AND m.organization_id = team_invitations.organization_id
        AND m.role IN ('owner', 'admin')
    )
  );

DROP POLICY IF EXISTS "Org admins can revoke invitations" ON public.team_invitations;
CREATE POLICY "Org admins can revoke invitations"
  ON public.team_invitations FOR DELETE
  USING (
    organization_id = public.get_user_organization_id()
    AND EXISTS (
      SELECT 1 FROM public.organization_memberships m
      WHERE m.user_id = auth.uid()
        AND m.organization_id = team_invitations.organization_id
        AND m.role IN ('owner', 'admin')
    )
  );

-- 2b. billing_integrations ---------------------------------------------------
-- RLS is already enabled in the baseline schema; we just need policies.

DROP POLICY IF EXISTS "Org members can view billing" ON public.billing_integrations;
CREATE POLICY "Org members can view billing"
  ON public.billing_integrations FOR SELECT
  USING (organization_id = public.get_user_organization_id());

DROP POLICY IF EXISTS "Org owners can manage billing" ON public.billing_integrations;
CREATE POLICY "Org owners can manage billing"
  ON public.billing_integrations FOR ALL
  USING (
    organization_id = public.get_user_organization_id()
    AND EXISTS (
      SELECT 1 FROM public.organization_memberships m
      WHERE m.user_id = auth.uid()
        AND m.organization_id = billing_integrations.organization_id
        AND m.role IN ('owner', 'admin')
    )
  )
  WITH CHECK (
    organization_id = public.get_user_organization_id()
    AND EXISTS (
      SELECT 1 FROM public.organization_memberships m
      WHERE m.user_id = auth.uid()
        AND m.organization_id = billing_integrations.organization_id
        AND m.role IN ('owner', 'admin')
    )
  );

-- 2c. *_sequences ------------------------------------------------------------
-- Internal counters. Simple org-membership gate.

ALTER TABLE public.incident_sequences ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Org members manage incident_sequences" ON public.incident_sequences;
CREATE POLICY "Org members manage incident_sequences"
  ON public.incident_sequences FOR ALL
  USING (organization_id = public.get_user_organization_id())
  WITH CHECK (organization_id = public.get_user_organization_id());

ALTER TABLE public.change_sequences ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Org members manage change_sequences" ON public.change_sequences;
CREATE POLICY "Org members manage change_sequences"
  ON public.change_sequences FOR ALL
  USING (organization_id = public.get_user_organization_id())
  WITH CHECK (organization_id = public.get_user_organization_id());

ALTER TABLE public.problem_sequences ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Org members manage problem_sequences" ON public.problem_sequences;
CREATE POLICY "Org members manage problem_sequences"
  ON public.problem_sequences FOR ALL
  USING (organization_id = public.get_user_organization_id())
  WITH CHECK (organization_id = public.get_user_organization_id());


-- ----------------------------------------------------------------------------
-- 3. CHECK constraints on enum-like text columns
-- ----------------------------------------------------------------------------
-- Today these are free-form `text`. Adding a CHECK locks the domain without
-- changing the column type (cheap, reversible).
-- ----------------------------------------------------------------------------

ALTER TABLE public.team_invitations
  DROP CONSTRAINT IF EXISTS team_invitations_status_check;
ALTER TABLE public.team_invitations
  ADD  CONSTRAINT team_invitations_status_check
       CHECK (status IN ('pending', 'accepted', 'expired', 'cancelled', 'revoked'));

ALTER TABLE public.team_invitations
  DROP CONSTRAINT IF EXISTS team_invitations_role_check;
ALTER TABLE public.team_invitations
  ADD  CONSTRAINT team_invitations_role_check
       CHECK (role IN ('owner', 'admin', 'manager', 'member', 'viewer'));

ALTER TABLE public.billing_integrations
  DROP CONSTRAINT IF EXISTS billing_integrations_subscription_status_check;
ALTER TABLE public.billing_integrations
  ADD  CONSTRAINT billing_integrations_subscription_status_check
       CHECK (
         subscription_status IS NULL
         OR subscription_status IN (
           'trialing', 'active', 'past_due', 'canceled',
           'unpaid', 'incomplete', 'incomplete_expired', 'paused'
         )
       );


-- ----------------------------------------------------------------------------
-- 4. Backfill missing updated_at triggers
-- ----------------------------------------------------------------------------
-- These tables have an `updated_at` column but no BEFORE UPDATE trigger.
-- Without the trigger the column is set on INSERT and never changes again,
-- which silently breaks "show last edit time" features and audits.
--
-- DROP IF EXISTS + CREATE keeps this idempotent. We use the existing
-- `update_updated_at_column()` helper.
-- ----------------------------------------------------------------------------

DROP TRIGGER IF EXISTS update_billing_integrations_updated_at      ON public.billing_integrations;
CREATE TRIGGER update_billing_integrations_updated_at
  BEFORE UPDATE ON public.billing_integrations
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_organization_memberships_updated_at  ON public.organization_memberships;
CREATE TRIGGER update_organization_memberships_updated_at
  BEFORE UPDATE ON public.organization_memberships
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_organizations_updated_at             ON public.organizations;
CREATE TRIGGER update_organizations_updated_at
  BEFORE UPDATE ON public.organizations
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_profiles_updated_at                  ON public.profiles;
CREATE TRIGGER update_profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_team_invitations_updated_at          ON public.team_invitations;
CREATE TRIGGER update_team_invitations_updated_at
  BEFORE UPDATE ON public.team_invitations
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- problems / incidents already have BEFORE UPDATE triggers
-- (`handle_problem_before_update`, `handle_incident_before_update`) that
-- handle their updated_at, so we skip them.
-- ai_cache and openai_usage_logs are append-mostly; deliberately no triggers.


-- ----------------------------------------------------------------------------
-- 5. Indexes on hot filter / FK columns
-- ----------------------------------------------------------------------------
-- Adds indexes that materially affect read performance for the dashboard
-- and list views. CREATE INDEX IF NOT EXISTS makes this safe to re-run.
-- We omit CONCURRENTLY because the migration file runs inside a transaction.
-- For a hot production DB, run these statements outside the transaction
-- with CONCURRENTLY — see the README in this directory.
-- ----------------------------------------------------------------------------

-- incidents
CREATE INDEX IF NOT EXISTS idx_incidents_status                ON public.incidents (status);
CREATE INDEX IF NOT EXISTS idx_incidents_created_by            ON public.incidents (created_by);
CREATE INDEX IF NOT EXISTS idx_incidents_assigned_to           ON public.incidents (assigned_to)
  WHERE assigned_to IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_incidents_org_status            ON public.incidents (organization_id, status);
CREATE INDEX IF NOT EXISTS idx_incidents_org_created_at        ON public.incidents (organization_id, created_at DESC);

-- changes
CREATE INDEX IF NOT EXISTS idx_changes_status                  ON public.changes (status);
CREATE INDEX IF NOT EXISTS idx_changes_requested_by            ON public.changes (requested_by);
CREATE INDEX IF NOT EXISTS idx_changes_assigned_to             ON public.changes (assigned_to)
  WHERE assigned_to IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_changes_org_status              ON public.changes (organization_id, status);
CREATE INDEX IF NOT EXISTS idx_changes_org_scheduled_for       ON public.changes (organization_id, scheduled_for)
  WHERE scheduled_for IS NOT NULL;

-- problems
CREATE INDEX IF NOT EXISTS idx_problems_status                 ON public.problems (status);
CREATE INDEX IF NOT EXISTS idx_problems_created_by             ON public.problems (created_by);
CREATE INDEX IF NOT EXISTS idx_problems_assigned_to            ON public.problems (assigned_to)
  WHERE assigned_to IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_problems_org_status             ON public.problems (organization_id, status);

-- team_invitations
CREATE INDEX IF NOT EXISTS idx_team_invitations_organization   ON public.team_invitations (organization_id);
CREATE INDEX IF NOT EXISTS idx_team_invitations_email          ON public.team_invitations (email);
CREATE INDEX IF NOT EXISTS idx_team_invitations_status         ON public.team_invitations (status);
CREATE INDEX IF NOT EXISTS idx_team_invitations_expires_at     ON public.team_invitations (expires_at)
  WHERE status = 'pending';

-- comments — already covered, but a composite by parent helps the dashboard
CREATE INDEX IF NOT EXISTS idx_comments_org_created_at         ON public.comments (organization_id, created_at DESC);


-- ----------------------------------------------------------------------------
-- 6. team_invitations.organization_id should be NOT NULL
-- ----------------------------------------------------------------------------
-- The column has a FK to organizations(id) but is currently nullable. Every
-- invitation belongs to exactly one org — leaving NULL allowed is a footgun.
--
-- Defensive: clean up any stray NULLs before tightening the column. Not
-- expected in production; included so the migration succeeds even on a
-- drifted dev DB.
-- ----------------------------------------------------------------------------

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'team_invitations'
      AND column_name  = 'organization_id'
      AND is_nullable  = 'YES'
  ) THEN
    DELETE FROM public.team_invitations WHERE organization_id IS NULL;
    ALTER TABLE public.team_invitations
      ALTER COLUMN organization_id SET NOT NULL;
  END IF;
END
$$;

COMMIT;

-- ============================================================================
-- Done.
--
-- Verification queries you can run after applying:
--
--   -- All 5 tables now have policies?
--   SELECT tablename, count(*) AS policies
--   FROM pg_policies
--   WHERE schemaname = 'public'
--     AND tablename IN ('billing_integrations','team_invitations',
--                       'incident_sequences','change_sequences','problem_sequences')
--   GROUP BY tablename;
--
--   -- All 10 SECURITY DEFINER funcs have a fixed search_path?
--   SELECT p.proname, p.proconfig
--   FROM pg_proc p
--   JOIN pg_namespace n ON n.oid = p.pronamespace
--   WHERE n.nspname = 'public' AND p.prosecdef = true
--   ORDER BY p.proname;
--
--   -- All new indexes present?
--   SELECT indexname FROM pg_indexes
--   WHERE schemaname = 'public'
--     AND indexname LIKE 'idx_%'
--   ORDER BY indexname;
-- ============================================================================
