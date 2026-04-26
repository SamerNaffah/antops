--
-- PostgreSQL database dump
--

-- Dumped from database version 17.4
-- Dumped by pg_dump version 17.7 (Homebrew)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: billing_tier_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.billing_tier_type AS ENUM (
    'free',
    'pro'
);


--
-- Name: change_status_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.change_status_type AS ENUM (
    'draft',
    'pending',
    'approved',
    'in_progress',
    'completed',
    'failed',
    'cancelled'
);


--
-- Name: incident_status_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.incident_status_type AS ENUM (
    'open',
    'investigating',
    'resolved',
    'closed'
);


--
-- Name: priority_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.priority_type AS ENUM (
    'low',
    'medium',
    'high',
    'critical'
);


--
-- Name: problem_status_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.problem_status_type AS ENUM (
    'identified',
    'investigating',
    'known_error',
    'resolved',
    'closed'
);


--
-- Name: user_role_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.user_role_type AS ENUM (
    'owner',
    'admin',
    'manager',
    'member',
    'viewer'
);


--
-- Name: calculate_priority(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.calculate_priority(criticality_val text, urgency_val text) RETURNS text
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- ITIL Priority Matrix
    -- Critical/Critical = Critical
    -- Critical/High = Critical, High/Critical = Critical
    -- Critical/Medium = High, Medium/Critical = High, High/High = High
    -- Everything else = Medium/Low based on combination
    
    CASE 
        WHEN criticality_val = 'critical' AND urgency_val = 'critical' THEN
            RETURN 'critical';
        WHEN (criticality_val = 'critical' AND urgency_val = 'high') OR 
             (criticality_val = 'high' AND urgency_val = 'critical') THEN
            RETURN 'critical';
        WHEN (criticality_val = 'critical' AND urgency_val = 'medium') OR
             (criticality_val = 'medium' AND urgency_val = 'critical') OR
             (criticality_val = 'high' AND urgency_val = 'high') THEN
            RETURN 'high';
        WHEN (criticality_val = 'critical' AND urgency_val = 'low') OR
             (criticality_val = 'low' AND urgency_val = 'critical') OR
             (criticality_val = 'high' AND urgency_val = 'medium') OR
             (criticality_val = 'medium' AND urgency_val = 'high') THEN
            RETURN 'medium';
        ELSE
            RETURN 'low';
    END CASE;
END;
$$;


--
-- Name: check_ai_scan_tokens(uuid, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_ai_scan_tokens(user_uuid uuid, required_tokens integer DEFAULT 1) RETURNS TABLE(has_tokens boolean, tokens_remaining integer, tokens_limit integer, reset_time timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    current_usage ai_scan_tokens%ROWTYPE;
BEGIN
    -- Get or create today's usage record
    SELECT * INTO current_usage
    FROM ai_scan_tokens
    WHERE user_id = user_uuid 
    AND date = CURRENT_DATE;
    
    -- If no record exists, create one
    IF NOT FOUND THEN
        INSERT INTO ai_scan_tokens (user_id, organization_id, date, tokens_used, tokens_limit)
        SELECT user_uuid, (SELECT organization_id FROM profiles WHERE id = user_uuid), CURRENT_DATE, 0, 5
        RETURNING * INTO current_usage;
    END IF;
    
    -- Calculate remaining tokens and reset time (midnight tomorrow)
    RETURN QUERY SELECT 
        (current_usage.tokens_used + required_tokens) <= current_usage.tokens_limit as has_tokens,
        GREATEST(0, current_usage.tokens_limit - current_usage.tokens_used) as tokens_remaining,
        current_usage.tokens_limit,
        (CURRENT_DATE + INTERVAL '1 day')::TIMESTAMP WITH TIME ZONE as reset_time;
END;
$$;


--
-- Name: check_and_update_billing_tiers(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_and_update_billing_tiers() RETURNS void
    LANGUAGE sql SECURITY DEFINER
    AS $$
  UPDATE organizations
  SET billing_tier = 'pro'
  WHERE billing_tier = 'free' 
    AND billing_expires_at < NOW()
    AND billing_expires_at IS NOT NULL;
$$;


--
-- Name: FUNCTION check_and_update_billing_tiers(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.check_and_update_billing_tiers() IS 'Automatically transitions expired free tiers to pro';


--
-- Name: clean_expired_ai_cache(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.clean_expired_ai_cache() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
  deleted_count INTEGER;
BEGIN
  DELETE FROM ai_cache 
  WHERE expires_at < NOW();
  
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$;


--
-- Name: cleanup_expired_api_tokens(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cleanup_expired_api_tokens() RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM api_tokens 
    WHERE expires_at IS NOT NULL 
    AND expires_at < NOW();
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$;


--
-- Name: consume_ai_scan_tokens(uuid, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.consume_ai_scan_tokens(user_uuid uuid, tokens_to_consume integer DEFAULT 1) RETURNS TABLE(success boolean, tokens_remaining integer, tokens_limit integer, message text)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    current_usage ai_scan_tokens%ROWTYPE;
    available_tokens INTEGER;
BEGIN
    -- Get today's usage record
    SELECT * INTO current_usage
    FROM ai_scan_tokens
    WHERE user_id = user_uuid 
    AND date = CURRENT_DATE;
    
    -- If no record exists, create one
    IF NOT FOUND THEN
        INSERT INTO ai_scan_tokens (user_id, organization_id, date, tokens_used, tokens_limit)
        SELECT user_uuid, (SELECT organization_id FROM profiles WHERE id = user_uuid), CURRENT_DATE, 0, 5
        RETURNING * INTO current_usage;
    END IF;
    
    available_tokens := current_usage.tokens_limit - current_usage.tokens_used;
    
    -- Check if user has enough tokens
    IF available_tokens >= tokens_to_consume THEN
        -- Consume tokens
        UPDATE ai_scan_tokens 
        SET tokens_used = tokens_used + tokens_to_consume
        WHERE user_id = user_uuid AND date = CURRENT_DATE;
        
        RETURN QUERY SELECT 
            TRUE as success,
            GREATEST(0, available_tokens - tokens_to_consume) as tokens_remaining,
            current_usage.tokens_limit,
            'Tokens consumed successfully'::TEXT as message;
    ELSE
        -- Not enough tokens
        RETURN QUERY SELECT 
            FALSE as success,
            available_tokens as tokens_remaining,
            current_usage.tokens_limit,
            'Insufficient AI scan tokens for today'::TEXT as message;
    END IF;
END;
$$;


--
-- Name: create_mention_notifications(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_mention_notifications() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  mentioned_user_id UUID;
BEGIN
  -- Only create notifications if mentions array is not empty
  IF NEW.mentions IS NOT NULL AND jsonb_array_length(NEW.mentions) > 0 THEN
    -- Loop through mentioned user IDs and create notifications
    FOR mentioned_user_id IN 
      SELECT jsonb_array_elements_text(NEW.mentions)::UUID
    LOOP
      -- Insert notification, but ignore if user tries to mention themselves
      IF mentioned_user_id != NEW.author_id THEN
        INSERT INTO comment_notifications (comment_id, user_id)
        VALUES (NEW.id, mentioned_user_id)
        ON CONFLICT DO NOTHING; -- Prevent duplicate notifications
      END IF;
    END LOOP;
  END IF;
  
  RETURN NEW;
END;
$$;


--
-- Name: generate_change_number(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.generate_change_number(org_id uuid) RETURNS text
    LANGUAGE plpgsql
    AS $$
  DECLARE
      org_prefix TEXT;
      next_num INTEGER;
      formatted_num TEXT;
  BEGIN
      -- Get organization prefix (first 3 letters in caps)
      SELECT UPPER(LEFT(name, 3)) INTO org_prefix
      FROM organizations
      WHERE id = org_id;

      -- Get or create next sequence number
      INSERT INTO change_sequences (organization_id, next_number)
      VALUES (org_id, 1)
      ON CONFLICT (organization_id) DO NOTHING;

      -- Get and increment the next number
      UPDATE change_sequences
      SET next_number = next_number + 1
      WHERE organization_id = org_id
      RETURNING next_number - 1 INTO next_num;

      -- Format with leading zeros
      formatted_num := LPAD(next_num::TEXT, 4, '0');

      -- Return formatted change number
      RETURN org_prefix || '-CHG-' || formatted_num;
  END;
  $$;


--
-- Name: generate_incident_number(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.generate_incident_number(org_id uuid) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    org_prefix TEXT;
    next_num INTEGER;
    formatted_num TEXT;
BEGIN
    -- Get organization prefix (first 3 letters in caps)
    SELECT UPPER(LEFT(name, 3)) INTO org_prefix
    FROM organizations 
    WHERE id = org_id;
    
    -- Get or create next sequence number
    INSERT INTO incident_sequences (organization_id, next_number)
    VALUES (org_id, 1)
    ON CONFLICT (organization_id) DO NOTHING;
    
    -- Get and increment the sequence
    UPDATE incident_sequences 
    SET next_number = next_number + 1
    WHERE organization_id = org_id
    RETURNING next_number - 1 INTO next_num;
    
    -- Format the number with leading zeros
    formatted_num := LPAD(next_num::TEXT, 4, '0');
    
    RETURN org_prefix || '-INC-' || formatted_num;
END;
$$;


--
-- Name: generate_problem_number(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.generate_problem_number(org_id uuid) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    org_prefix TEXT;
    next_num INTEGER;
    formatted_num TEXT;
BEGIN
    -- Get organization prefix (first 3 letters in caps)
    SELECT UPPER(LEFT(name, 3)) INTO org_prefix
    FROM organizations 
    WHERE id = org_id;
    
    -- Get or create next sequence number
    INSERT INTO problem_sequences (organization_id, next_number)
    VALUES (org_id, 1)
    ON CONFLICT (organization_id) DO NOTHING;
    
    -- Get and increment the sequence
    UPDATE problem_sequences 
    SET next_number = next_number + 1
    WHERE organization_id = org_id
    RETURNING next_number - 1 INTO next_num;
    
    -- Format the number with leading zeros
    formatted_num := LPAD(next_num::TEXT, 4, '0');
    
    RETURN org_prefix || '-PRBM-' || formatted_num;
END;
$$;


--
-- Name: get_user_ai_scan_status(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_user_ai_scan_status(user_uuid uuid) RETURNS TABLE(tokens_used integer, tokens_remaining integer, tokens_limit integer, reset_time timestamp with time zone, can_scan boolean)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    current_usage ai_scan_tokens%ROWTYPE;
BEGIN
    -- Get today's usage record
    SELECT * INTO current_usage
    FROM ai_scan_tokens
    WHERE user_id = user_uuid 
    AND date = CURRENT_DATE;
    
    -- If no record exists, return default values
    IF NOT FOUND THEN
        RETURN QUERY SELECT 
            0 as tokens_used,
            5 as tokens_remaining,
            5 as tokens_limit,
            (CURRENT_DATE + INTERVAL '1 day')::TIMESTAMP WITH TIME ZONE as reset_time,
            TRUE as can_scan;
    ELSE
        RETURN QUERY SELECT 
            current_usage.tokens_used,
            GREATEST(0, current_usage.tokens_limit - current_usage.tokens_used) as tokens_remaining,
            current_usage.tokens_limit,
            (CURRENT_DATE + INTERVAL '1 day')::TIMESTAMP WITH TIME ZONE as reset_time,
            (current_usage.tokens_used < current_usage.tokens_limit) as can_scan;
    END IF;
END;
$$;


--
-- Name: get_user_organization_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_user_organization_id() RETURNS uuid
    LANGUAGE sql SECURITY DEFINER
    AS $$
  SELECT organization_id FROM profiles WHERE id = auth.uid();
$$;


--
-- Name: handle_change_before_insert(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_change_before_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  BEGIN
      -- Generate change number if not provided
      IF NEW.change_number IS NULL THEN
          NEW.change_number := generate_change_number(NEW.organization_id);
      END IF;

      RETURN NEW;
  END;
  $$;


--
-- Name: handle_incident_before_insert(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_incident_before_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Generate incident number if not provided
    IF NEW.incident_number IS NULL THEN
        NEW.incident_number := generate_incident_number(NEW.organization_id);
    END IF;
    
    -- Calculate priority if auto_priority is true and we have criticality/urgency
    IF NEW.auto_priority = true AND NEW.criticality IS NOT NULL AND NEW.urgency IS NOT NULL THEN
        NEW.priority := calculate_priority(NEW.criticality, NEW.urgency);
    END IF;
    
    RETURN NEW;
END;
$$;


--
-- Name: handle_incident_before_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_incident_before_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Recalculate priority if auto_priority is true and criticality/urgency changed
    IF NEW.auto_priority = true AND 
       (NEW.criticality != OLD.criticality OR NEW.urgency != OLD.urgency) AND
       NEW.criticality IS NOT NULL AND NEW.urgency IS NOT NULL THEN
        NEW.priority := calculate_priority(NEW.criticality, NEW.urgency);
    END IF;
    
    RETURN NEW;
END;
$$;


--
-- Name: handle_new_user(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_new_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
  org_id UUID;
  org_name TEXT;
BEGIN
  -- Extract organization name from email domain or use a default
  org_name := COALESCE(
    NEW.raw_user_meta_data->>'organization_name',
    split_part(NEW.email, '@', 2)
  );
  
  -- Create organization if this is the first user (owner)
  INSERT INTO public.organizations (name, slug)
  VALUES (
    org_name,
    lower(replace(org_name, ' ', '-')) || '-' || substring(gen_random_uuid()::text, 1, 8)
  )
  RETURNING id INTO org_id;
  
  -- Create profile
  INSERT INTO public.profiles (
    id, 
    email, 
    full_name, 
    organization_id, 
    role
  )
  VALUES (
    NEW.id, 
    NEW.email, 
    COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)),
    org_id,
    'owner' -- First user becomes owner
  );
  
  RETURN NEW;
END;
$$;


--
-- Name: handle_problem_before_insert(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_problem_before_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Generate problem number if not provided
    IF NEW.problem_number IS NULL THEN
        NEW.problem_number := generate_problem_number(NEW.organization_id);
    END IF;
    
    -- Calculate priority if auto_priority is true and we have criticality/urgency
    IF NEW.auto_priority = true AND NEW.criticality IS NOT NULL AND NEW.urgency IS NOT NULL THEN
        NEW.priority := calculate_priority(NEW.criticality, NEW.urgency);
    END IF;
    
    RETURN NEW;
END;
$$;


--
-- Name: handle_problem_before_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_problem_before_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Recalculate priority if auto_priority is true and criticality/urgency changed
    IF NEW.auto_priority = true AND 
       (NEW.criticality != OLD.criticality OR NEW.urgency != OLD.urgency) AND
       NEW.criticality IS NOT NULL AND NEW.urgency IS NOT NULL THEN
        NEW.priority := calculate_priority(NEW.criticality, NEW.urgency);
    END IF;
    
    RETURN NEW;
END;
$$;


--
-- Name: set_billing_expiration(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_billing_expiration() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
  -- Set free tier to expire 2 months from creation
  IF NEW.billing_tier = 'free' AND NEW.billing_expires_at IS NULL THEN
    NEW.billing_expires_at = NEW.created_at + INTERVAL '2 months';
  END IF;
  
  RETURN NEW;
END;
$$;


--
-- Name: FUNCTION set_billing_expiration(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.set_billing_expiration() IS 'Sets billing expiration for new free tier organizations';


--
-- Name: update_ai_scan_tokens_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_ai_scan_tokens_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


--
-- Name: update_api_tokens_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_api_tokens_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


--
-- Name: update_cache_access(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_cache_access(cache_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
  UPDATE ai_cache 
  SET last_accessed = NOW(), 
      access_count = access_count + 1
  WHERE id = cache_id;
END;
$$;


--
-- Name: update_grafana_integrations_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_grafana_integrations_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;


--
-- Name: update_sla_configurations_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_sla_configurations_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = timezone('utc'::text, now());
    RETURN NEW;
END;
$$;


--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


--
-- Name: update_zone_hierarchy(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_zone_hierarchy() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Update depth and path for the modified zone
  WITH RECURSIVE zone_hierarchy AS (
    -- Base case: root zones (no parent)
    SELECT 
      id, 
      0 as depth,
      ARRAY[id] as path
    FROM infrastructure_zones 
    WHERE parent_zone_id IS NULL
    
    UNION ALL
    
    -- Recursive case: child zones
    SELECT 
      z.id,
      zh.depth + 1,
      zh.path || z.id
    FROM infrastructure_zones z
    JOIN zone_hierarchy zh ON z.parent_zone_id = zh.id
  )
  UPDATE infrastructure_zones 
  SET 
    zone_depth = zh.depth,
    zone_path = zh.path
  FROM zone_hierarchy zh
  WHERE infrastructure_zones.id = zh.id;
  
  RETURN NEW;
END;
$$;


--
-- Name: user_has_org_access(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.user_has_org_access(org_id uuid) RETURNS boolean
    LANGUAGE sql SECURITY DEFINER
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles 
    WHERE id = auth.uid() 
    AND organization_id = org_id
  );
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: ai_cache; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_cache (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    cache_key text NOT NULL,
    cache_type text NOT NULL,
    input_hash text NOT NULL,
    ai_response jsonb NOT NULL,
    confidence_score numeric(3,2),
    token_usage jsonb,
    cost numeric(10,8),
    created_at timestamp with time zone DEFAULT now(),
    expires_at timestamp with time zone,
    last_accessed timestamp with time zone DEFAULT now(),
    access_count integer DEFAULT 1
);


--
-- Name: TABLE ai_cache; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.ai_cache IS 'Caches AI responses to optimize performance and reduce costs';


--
-- Name: COLUMN ai_cache.cache_key; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ai_cache.cache_key IS 'Unique key generated from input parameters';


--
-- Name: COLUMN ai_cache.cache_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ai_cache.cache_type IS 'Type of AI analysis (incident_analysis, change_impact, etc.)';


--
-- Name: COLUMN ai_cache.input_hash; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ai_cache.input_hash IS 'Hash of input data to validate cache validity';


--
-- Name: COLUMN ai_cache.ai_response; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ai_cache.ai_response IS 'Structured AI response data';


--
-- Name: COLUMN ai_cache.confidence_score; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ai_cache.confidence_score IS 'AI confidence level from 0.00 to 1.00';


--
-- Name: COLUMN ai_cache.expires_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ai_cache.expires_at IS 'When this cache entry expires (NULL = never expires)';


--
-- Name: ai_scan_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_scan_tokens (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    date date DEFAULT CURRENT_DATE NOT NULL,
    tokens_used integer DEFAULT 0,
    tokens_limit integer DEFAULT 5,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: api_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_tokens (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    name character varying(255) NOT NULL,
    token_hash text NOT NULL,
    token_prefix character varying(20) NOT NULL,
    permissions jsonb DEFAULT '["read", "write"]'::jsonb,
    scope text DEFAULT 'full'::text,
    last_used_at timestamp with time zone,
    last_used_ip inet,
    usage_count integer DEFAULT 0,
    expires_at timestamp with time zone,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: billing_integrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.billing_integrations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    enabled boolean DEFAULT false,
    stripe_customer_id text,
    subscription_id text,
    subscription_status text,
    current_plan text DEFAULT 'free'::text,
    billing_email text,
    billing_interval text,
    price_id text,
    seats_limit integer DEFAULT 5,
    incidents_limit integer DEFAULT 100,
    storage_limit integer DEFAULT 1,
    current_period_start timestamp with time zone,
    current_period_end timestamp with time zone,
    trial_end timestamp with time zone,
    cancel_at timestamp with time zone,
    canceled_at timestamp with time zone,
    metadata jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: change_approvals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.change_approvals (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    change_id uuid NOT NULL,
    requested_by uuid NOT NULL,
    approved_by uuid,
    status text DEFAULT 'pending'::text NOT NULL,
    comments text,
    requested_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    responded_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    CONSTRAINT change_approvals_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])))
);


--
-- Name: TABLE change_approvals; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.change_approvals IS 'Tracks approval requests and responses for changes';


--
-- Name: change_automations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.change_automations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    change_id uuid NOT NULL,
    automation_type text NOT NULL,
    scheduled_for timestamp with time zone NOT NULL,
    executed boolean DEFAULT false,
    executed_at timestamp with time zone,
    error_message text,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    CONSTRAINT change_automations_automation_type_check CHECK ((automation_type = ANY (ARRAY['auto_start'::text, 'completion_prompt'::text])))
);


--
-- Name: TABLE change_automations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.change_automations IS 'Scheduled automation jobs for changes';


--
-- Name: change_completion_responses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.change_completion_responses (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    change_id uuid NOT NULL,
    responded_by uuid NOT NULL,
    outcome text NOT NULL,
    notes text,
    responded_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    CONSTRAINT change_completion_responses_outcome_check CHECK ((outcome = ANY (ARRAY['completed'::text, 'failed'::text])))
);


--
-- Name: TABLE change_completion_responses; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.change_completion_responses IS 'User responses about change completion status';


--
-- Name: change_sequences; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.change_sequences (
    organization_id uuid NOT NULL,
    next_number integer DEFAULT 1
);


--
-- Name: changes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.changes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    title text NOT NULL,
    description text NOT NULL,
    status public.change_status_type DEFAULT 'draft'::public.change_status_type NOT NULL,
    priority public.priority_type DEFAULT 'medium'::public.priority_type NOT NULL,
    requested_by uuid NOT NULL,
    assigned_to uuid,
    scheduled_for timestamp with time zone,
    rollback_plan text NOT NULL,
    test_plan text NOT NULL,
    tags text[] DEFAULT '{}'::text[],
    affected_services text[] DEFAULT '{}'::text[],
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    completed_at timestamp with time zone,
    problem_id uuid,
    incident_id uuid,
    estimated_end_time timestamp with time zone,
    change_number text,
    attachments jsonb DEFAULT '[]'::jsonb
);


--
-- Name: COLUMN changes.estimated_end_time; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.changes.estimated_end_time IS 'Expected end time for the maintenance window of this change';


--
-- Name: COLUMN changes.attachments; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.changes.attachments IS 'JSON array of file attachments. Each attachment object contains: id, name, size, type, url';


--
-- Name: comment_notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.comment_notifications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    comment_id uuid NOT NULL,
    user_id uuid NOT NULL,
    is_read boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: comments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.comments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    content text NOT NULL,
    author_id uuid NOT NULL,
    incident_id uuid,
    problem_id uuid,
    change_id uuid,
    mentions jsonb DEFAULT '[]'::jsonb,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    attachments jsonb DEFAULT '[]'::jsonb,
    CONSTRAINT chk_comment_single_reference CHECK ((((((incident_id IS NOT NULL))::integer + ((problem_id IS NOT NULL))::integer) + ((change_id IS NOT NULL))::integer) = 1))
);


--
-- Name: COLUMN comments.attachments; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.comments.attachments IS 'JSON array of file attachments. Each attachment object contains: id, name, size, type, url';


--
-- Name: grafana_integrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.grafana_integrations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    enabled boolean DEFAULT false NOT NULL,
    webhook_url text NOT NULL,
    api_key text,
    auto_create_incidents boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: TABLE grafana_integrations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.grafana_integrations IS 'Stores Grafana integration configuration for organizations';


--
-- Name: COLUMN grafana_integrations.webhook_url; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.grafana_integrations.webhook_url IS 'URL for receiving Grafana webhook notifications';


--
-- Name: COLUMN grafana_integrations.api_key; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.grafana_integrations.api_key IS 'Optional API key for validating webhook requests';


--
-- Name: COLUMN grafana_integrations.auto_create_incidents; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.grafana_integrations.auto_create_incidents IS 'Whether to automatically create incidents when users click notifications';


--
-- Name: incident_sequences; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.incident_sequences (
    organization_id uuid NOT NULL,
    next_number integer DEFAULT 1
);


--
-- Name: incidents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.incidents (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    title text NOT NULL,
    description text NOT NULL,
    priority public.priority_type DEFAULT 'medium'::public.priority_type NOT NULL,
    status public.incident_status_type DEFAULT 'open'::public.incident_status_type NOT NULL,
    assigned_to uuid,
    created_by uuid NOT NULL,
    problem_id uuid,
    tags text[] DEFAULT '{}'::text[],
    affected_services text[] DEFAULT '{}'::text[],
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    resolved_at timestamp with time zone,
    criticality text,
    urgency text,
    incident_number text,
    auto_priority boolean DEFAULT true,
    links jsonb DEFAULT '[]'::jsonb,
    attachments jsonb DEFAULT '[]'::jsonb,
    customer text,
    CONSTRAINT incidents_criticality_check CHECK ((criticality = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text, 'critical'::text]))),
    CONSTRAINT incidents_urgency_check CHECK ((urgency = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text, 'critical'::text])))
);


--
-- Name: COLUMN incidents.links; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.incidents.links IS 'Array of external links to Zendesk tickets, JIRA cards, etc. Format: [{"title": "string", "url": "string", "type": "zendesk|jira|other"}]';


--
-- Name: COLUMN incidents.attachments; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.incidents.attachments IS 'JSON array of file attachments. Each attachment object contains: id, name, size, type, url';


--
-- Name: infrastructure_edges; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.infrastructure_edges (
    id text NOT NULL,
    organization_id uuid NOT NULL,
    source text NOT NULL,
    target text NOT NULL,
    relationship text DEFAULT 'connected'::text NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    environment_id uuid
);


--
-- Name: infrastructure_environments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.infrastructure_environments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    name text NOT NULL,
    description text,
    is_default boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


--
-- Name: infrastructure_nodes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.infrastructure_nodes (
    id text NOT NULL,
    organization_id uuid NOT NULL,
    type text NOT NULL,
    label text NOT NULL,
    position_x double precision DEFAULT 0 NOT NULL,
    position_y double precision DEFAULT 0 NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    environment_id uuid,
    zone_constraint text DEFAULT 'none'::text,
    zone_id text,
    CONSTRAINT infrastructure_nodes_zone_constraint_check CHECK ((zone_constraint = ANY (ARRAY['none'::text, 'parent'::text, 'strict'::text])))
);


--
-- Name: infrastructure_zones; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.infrastructure_zones (
    id text NOT NULL,
    organization_id uuid NOT NULL,
    environment_id uuid NOT NULL,
    name text NOT NULL,
    description text,
    zone_type text NOT NULL,
    parent_zone_id text,
    zone_depth integer DEFAULT 0,
    zone_path text[],
    position_x double precision DEFAULT 0 NOT NULL,
    position_y double precision DEFAULT 0 NOT NULL,
    width double precision DEFAULT 300,
    height double precision DEFAULT 200,
    zone_config jsonb DEFAULT '{}'::jsonb,
    style_config jsonb DEFAULT '{}'::jsonb,
    tags text[] DEFAULT '{}'::text[],
    is_collapsed boolean DEFAULT false,
    is_locked boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    CONSTRAINT infrastructure_zones_check CHECK ((parent_zone_id <> id)),
    CONSTRAINT infrastructure_zones_zone_depth_check CHECK (((zone_depth >= 0) AND (zone_depth <= 10))),
    CONSTRAINT infrastructure_zones_zone_type_check CHECK ((zone_type = ANY (ARRAY['vpc'::text, 'subnet'::text, 'lan'::text, 'wan'::text, 'vlan'::text, 'dmz'::text, 'security_group'::text, 'network_acl'::text, 'security_zone'::text, 'trust_zone'::text, 'untrust_zone'::text, 'datacenter'::text, 'availability_zone'::text, 'region'::text, 'rack'::text, 'cluster'::text, 'namespace'::text, 'resource_group'::text, 'application'::text, 'service_mesh'::text, 'microservice'::text, 'environment_tier'::text, 'custom'::text, 'aws_vpc'::text, 'aws_subnet'::text, 'aws_security_group'::text, 'aws_ecs_cluster'::text, 'aws_eks_cluster'::text, 'aws_db_subnet_group'::text, 'aws_internet_gateway'::text, 'aws_nat_gateway'::text, 'aws_route_table'::text, 'azurerm_virtual_network'::text, 'azurerm_subnet'::text, 'azurerm_network_security_group'::text, 'azurerm_resource_group'::text, 'azurerm_kubernetes_cluster'::text, 'google_compute_network'::text, 'google_compute_subnetwork'::text, 'google_container_cluster'::text, 'google_compute_firewall'::text])))
);


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notifications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    user_id uuid NOT NULL,
    type text NOT NULL,
    title text NOT NULL,
    message text NOT NULL,
    data jsonb DEFAULT '{}'::jsonb,
    read boolean DEFAULT false,
    change_id uuid,
    incident_id uuid,
    problem_id uuid,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    last_attempt_at timestamp with time zone,
    sent_at timestamp with time zone,
    error text,
    CONSTRAINT notifications_type_check CHECK ((type = ANY (ARRAY['change_approval_request'::text, 'change_approved'::text, 'change_rejected'::text, 'change_completion_prompt'::text, 'change_auto_started'::text])))
);


--
-- Name: TABLE notifications; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.notifications IS 'In-app notifications for users';


--
-- Name: openai_usage_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.openai_usage_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    model text NOT NULL,
    input_tokens integer DEFAULT 0 NOT NULL,
    output_tokens integer DEFAULT 0 NOT NULL,
    total_tokens integer DEFAULT 0 NOT NULL,
    cost numeric(10,8) DEFAULT 0 NOT NULL,
    endpoint text NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: TABLE openai_usage_logs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.openai_usage_logs IS 'Tracks OpenAI API usage for cost monitoring and analytics';


--
-- Name: COLUMN openai_usage_logs.organization_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.openai_usage_logs.organization_id IS 'Organization that made the OpenAI request';


--
-- Name: COLUMN openai_usage_logs.model; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.openai_usage_logs.model IS 'OpenAI model used (e.g., gpt-4o-mini)';


--
-- Name: COLUMN openai_usage_logs.input_tokens; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.openai_usage_logs.input_tokens IS 'Number of input tokens (prompt)';


--
-- Name: COLUMN openai_usage_logs.output_tokens; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.openai_usage_logs.output_tokens IS 'Number of output tokens (completion)';


--
-- Name: COLUMN openai_usage_logs.total_tokens; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.openai_usage_logs.total_tokens IS 'Total tokens used (input + output)';


--
-- Name: COLUMN openai_usage_logs.cost; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.openai_usage_logs.cost IS 'Cost in USD for this request';


--
-- Name: COLUMN openai_usage_logs.endpoint; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.openai_usage_logs.endpoint IS 'API endpoint that made the request (for tracking usage by feature)';


--
-- Name: organization_memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organization_memberships (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    organization_id uuid,
    role public.user_role_type DEFAULT 'member'::public.user_role_type NOT NULL,
    invited_by uuid,
    invited_at timestamp with time zone DEFAULT timezone('utc'::text, now()),
    joined_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


--
-- Name: organizations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organizations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    slug text NOT NULL,
    description text,
    settings jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    billing_tier public.billing_tier_type DEFAULT 'free'::public.billing_tier_type NOT NULL,
    billing_expires_at timestamp with time zone
);


--
-- Name: COLUMN organizations.billing_tier; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.organizations.billing_tier IS 'Current billing tier: free (2-month pilot) or pro (paid)';


--
-- Name: COLUMN organizations.billing_expires_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.organizations.billing_expires_at IS 'When free tier expires and auto-transitions to pro';


--
-- Name: pagerduty_integrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pagerduty_integrations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    enabled boolean DEFAULT false NOT NULL,
    webhook_url text NOT NULL,
    api_key text,
    routing_key text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: problem_sequences; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.problem_sequences (
    organization_id uuid NOT NULL,
    next_number integer DEFAULT 1
);


--
-- Name: problems; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.problems (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    title text NOT NULL,
    description text NOT NULL,
    priority public.priority_type DEFAULT 'medium'::public.priority_type NOT NULL,
    status public.problem_status_type DEFAULT 'identified'::public.problem_status_type NOT NULL,
    assigned_to uuid,
    created_by uuid NOT NULL,
    root_cause text,
    workaround text,
    solution text,
    tags text[] DEFAULT '{}'::text[],
    affected_services text[] DEFAULT '{}'::text[],
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    resolved_at timestamp with time zone,
    criticality text,
    urgency text,
    problem_number text,
    auto_priority boolean DEFAULT true,
    attachments jsonb DEFAULT '[]'::jsonb,
    CONSTRAINT problems_criticality_check CHECK ((criticality = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text, 'critical'::text]))),
    CONSTRAINT problems_urgency_check CHECK ((urgency = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text, 'critical'::text])))
);


--
-- Name: COLUMN problems.attachments; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.problems.attachments IS 'JSON array of file attachments. Each attachment object contains: id, name, size, type, url';


--
-- Name: profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.profiles (
    id uuid NOT NULL,
    email text NOT NULL,
    full_name text,
    avatar_url text,
    organization_id uuid,
    role public.user_role_type DEFAULT 'member'::public.user_role_type NOT NULL,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    job_title text
);


--
-- Name: slo_configurations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.slo_configurations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    priority public.priority_type NOT NULL,
    resolution_time_hours integer DEFAULT 24 NOT NULL,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


--
-- Name: team_invitations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.team_invitations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid,
    email text NOT NULL,
    role text NOT NULL,
    invited_by uuid,
    invite_token text NOT NULL,
    status text DEFAULT 'pending'::text,
    expires_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: user_organization_stats; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.user_organization_stats AS
 SELECT o.id AS organization_id,
    o.name AS organization_name,
    count(DISTINCT p.id) AS total_members,
    count(DISTINCT
        CASE
            WHEN (i.status <> 'closed'::public.incident_status_type) THEN i.id
            ELSE NULL::uuid
        END) AS open_incidents,
    count(DISTINCT
        CASE
            WHEN (pr.status <> ALL (ARRAY['resolved'::public.problem_status_type, 'closed'::public.problem_status_type])) THEN pr.id
            ELSE NULL::uuid
        END) AS active_problems,
    count(DISTINCT
        CASE
            WHEN (c.status = ANY (ARRAY['in_progress'::public.change_status_type, 'pending'::public.change_status_type])) THEN c.id
            ELSE NULL::uuid
        END) AS active_changes
   FROM ((((public.organizations o
     LEFT JOIN public.profiles p ON ((p.organization_id = o.id)))
     LEFT JOIN public.incidents i ON ((i.organization_id = o.id)))
     LEFT JOIN public.problems pr ON ((pr.organization_id = o.id)))
     LEFT JOIN public.changes c ON ((c.organization_id = o.id)))
  GROUP BY o.id, o.name;


--
-- Name: ai_cache ai_cache_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_cache
    ADD CONSTRAINT ai_cache_pkey PRIMARY KEY (id);


--
-- Name: ai_scan_tokens ai_scan_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_scan_tokens
    ADD CONSTRAINT ai_scan_tokens_pkey PRIMARY KEY (id);


--
-- Name: ai_scan_tokens ai_scan_tokens_user_id_date_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_scan_tokens
    ADD CONSTRAINT ai_scan_tokens_user_id_date_key UNIQUE (user_id, date);


--
-- Name: api_tokens api_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_tokens
    ADD CONSTRAINT api_tokens_pkey PRIMARY KEY (id);


--
-- Name: api_tokens api_tokens_token_hash_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_tokens
    ADD CONSTRAINT api_tokens_token_hash_key UNIQUE (token_hash);


--
-- Name: billing_integrations billing_integrations_organization_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_integrations
    ADD CONSTRAINT billing_integrations_organization_id_key UNIQUE (organization_id);


--
-- Name: billing_integrations billing_integrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_integrations
    ADD CONSTRAINT billing_integrations_pkey PRIMARY KEY (id);


--
-- Name: change_approvals change_approvals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.change_approvals
    ADD CONSTRAINT change_approvals_pkey PRIMARY KEY (id);


--
-- Name: change_automations change_automations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.change_automations
    ADD CONSTRAINT change_automations_pkey PRIMARY KEY (id);


--
-- Name: change_completion_responses change_completion_responses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.change_completion_responses
    ADD CONSTRAINT change_completion_responses_pkey PRIMARY KEY (id);


--
-- Name: change_sequences change_sequences_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.change_sequences
    ADD CONSTRAINT change_sequences_pkey PRIMARY KEY (organization_id);


--
-- Name: changes changes_change_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.changes
    ADD CONSTRAINT changes_change_number_key UNIQUE (change_number);


--
-- Name: changes changes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.changes
    ADD CONSTRAINT changes_pkey PRIMARY KEY (id);


--
-- Name: comment_notifications comment_notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comment_notifications
    ADD CONSTRAINT comment_notifications_pkey PRIMARY KEY (id);


--
-- Name: comments comments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_pkey PRIMARY KEY (id);


--
-- Name: grafana_integrations grafana_integrations_organization_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grafana_integrations
    ADD CONSTRAINT grafana_integrations_organization_id_key UNIQUE (organization_id);


--
-- Name: grafana_integrations grafana_integrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grafana_integrations
    ADD CONSTRAINT grafana_integrations_pkey PRIMARY KEY (id);


--
-- Name: incident_sequences incident_sequences_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.incident_sequences
    ADD CONSTRAINT incident_sequences_pkey PRIMARY KEY (organization_id);


--
-- Name: incidents incidents_incident_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.incidents
    ADD CONSTRAINT incidents_incident_number_key UNIQUE (incident_number);


--
-- Name: incidents incidents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.incidents
    ADD CONSTRAINT incidents_pkey PRIMARY KEY (id);


--
-- Name: infrastructure_edges infrastructure_edges_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.infrastructure_edges
    ADD CONSTRAINT infrastructure_edges_pkey PRIMARY KEY (id);


--
-- Name: infrastructure_environments infrastructure_environments_organization_id_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.infrastructure_environments
    ADD CONSTRAINT infrastructure_environments_organization_id_name_key UNIQUE (organization_id, name);


--
-- Name: infrastructure_environments infrastructure_environments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.infrastructure_environments
    ADD CONSTRAINT infrastructure_environments_pkey PRIMARY KEY (id);


--
-- Name: infrastructure_nodes infrastructure_nodes_env_id_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.infrastructure_nodes
    ADD CONSTRAINT infrastructure_nodes_env_id_unique UNIQUE (environment_id, id);


--
-- Name: infrastructure_nodes infrastructure_nodes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.infrastructure_nodes
    ADD CONSTRAINT infrastructure_nodes_pkey PRIMARY KEY (id);


--
-- Name: infrastructure_zones infrastructure_zones_organization_id_environment_id_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.infrastructure_zones
    ADD CONSTRAINT infrastructure_zones_organization_id_environment_id_name_key UNIQUE (organization_id, environment_id, name);


--
-- Name: infrastructure_zones infrastructure_zones_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.infrastructure_zones
    ADD CONSTRAINT infrastructure_zones_pkey PRIMARY KEY (id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: openai_usage_logs openai_usage_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.openai_usage_logs
    ADD CONSTRAINT openai_usage_logs_pkey PRIMARY KEY (id);


--
-- Name: organization_memberships organization_memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_memberships
    ADD CONSTRAINT organization_memberships_pkey PRIMARY KEY (id);


--
-- Name: organization_memberships organization_memberships_user_id_organization_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_memberships
    ADD CONSTRAINT organization_memberships_user_id_organization_id_key UNIQUE (user_id, organization_id);


--
-- Name: organizations organizations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_pkey PRIMARY KEY (id);


--
-- Name: organizations organizations_slug_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_slug_key UNIQUE (slug);


--
-- Name: pagerduty_integrations pagerduty_integrations_organization_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pagerduty_integrations
    ADD CONSTRAINT pagerduty_integrations_organization_id_key UNIQUE (organization_id);


--
-- Name: pagerduty_integrations pagerduty_integrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pagerduty_integrations
    ADD CONSTRAINT pagerduty_integrations_pkey PRIMARY KEY (id);


--
-- Name: problem_sequences problem_sequences_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.problem_sequences
    ADD CONSTRAINT problem_sequences_pkey PRIMARY KEY (organization_id);


--
-- Name: problems problems_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.problems
    ADD CONSTRAINT problems_pkey PRIMARY KEY (id);


--
-- Name: problems problems_problem_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.problems
    ADD CONSTRAINT problems_problem_number_key UNIQUE (problem_number);


--
-- Name: profiles profiles_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_email_key UNIQUE (email);


--
-- Name: profiles profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);


--
-- Name: slo_configurations sla_configurations_organization_id_priority_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.slo_configurations
    ADD CONSTRAINT sla_configurations_organization_id_priority_key UNIQUE (organization_id, priority);


--
-- Name: slo_configurations sla_configurations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.slo_configurations
    ADD CONSTRAINT sla_configurations_pkey PRIMARY KEY (id);


--
-- Name: team_invitations team_invitations_invite_token_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_invitations
    ADD CONSTRAINT team_invitations_invite_token_key UNIQUE (invite_token);


--
-- Name: team_invitations team_invitations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_invitations
    ADD CONSTRAINT team_invitations_pkey PRIMARY KEY (id);


--
-- Name: idx_ai_cache_cache_key; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_cache_cache_key ON public.ai_cache USING btree (cache_key);


--
-- Name: idx_ai_cache_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_cache_expires_at ON public.ai_cache USING btree (expires_at);


--
-- Name: idx_ai_cache_input_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_cache_input_hash ON public.ai_cache USING btree (input_hash);


--
-- Name: idx_ai_cache_org_type_key; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_cache_org_type_key ON public.ai_cache USING btree (organization_id, cache_type, cache_key);


--
-- Name: idx_ai_cache_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_cache_organization_id ON public.ai_cache USING btree (organization_id);


--
-- Name: idx_ai_cache_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_cache_type ON public.ai_cache USING btree (cache_type);


--
-- Name: idx_ai_scan_tokens_organization; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_scan_tokens_organization ON public.ai_scan_tokens USING btree (organization_id);


--
-- Name: idx_ai_scan_tokens_user_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_scan_tokens_user_date ON public.ai_scan_tokens USING btree (user_id, date);


--
-- Name: idx_api_tokens_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_api_tokens_active ON public.api_tokens USING btree (is_active) WHERE (is_active = true);


--
-- Name: idx_api_tokens_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_api_tokens_expires_at ON public.api_tokens USING btree (expires_at) WHERE (expires_at IS NOT NULL);


--
-- Name: idx_api_tokens_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_api_tokens_organization_id ON public.api_tokens USING btree (organization_id);


--
-- Name: idx_api_tokens_token_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_api_tokens_token_hash ON public.api_tokens USING btree (token_hash);


--
-- Name: idx_api_tokens_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_api_tokens_user_id ON public.api_tokens USING btree (user_id);


--
-- Name: idx_change_approvals_change_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_change_approvals_change_id ON public.change_approvals USING btree (change_id);


--
-- Name: idx_change_approvals_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_change_approvals_organization_id ON public.change_approvals USING btree (organization_id);


--
-- Name: idx_change_approvals_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_change_approvals_status ON public.change_approvals USING btree (status);


--
-- Name: idx_change_automations_executed; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_change_automations_executed ON public.change_automations USING btree (executed);


--
-- Name: idx_change_automations_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_change_automations_organization_id ON public.change_automations USING btree (organization_id);


--
-- Name: idx_change_automations_scheduled_for; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_change_automations_scheduled_for ON public.change_automations USING btree (scheduled_for);


--
-- Name: idx_change_completion_responses_change_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_change_completion_responses_change_id ON public.change_completion_responses USING btree (change_id);


--
-- Name: idx_change_completion_responses_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_change_completion_responses_organization_id ON public.change_completion_responses USING btree (organization_id);


--
-- Name: idx_changes_attachments; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_changes_attachments ON public.changes USING gin (attachments);


--
-- Name: idx_changes_estimated_end_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_changes_estimated_end_time ON public.changes USING btree (estimated_end_time);


--
-- Name: idx_changes_incident_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_changes_incident_id ON public.changes USING btree (incident_id);


--
-- Name: idx_changes_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_changes_organization_id ON public.changes USING btree (organization_id);


--
-- Name: idx_changes_problem_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_changes_problem_id ON public.changes USING btree (problem_id);


--
-- Name: idx_comment_notifications_comment_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_comment_notifications_comment_id ON public.comment_notifications USING btree (comment_id);


--
-- Name: idx_comment_notifications_is_read; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_comment_notifications_is_read ON public.comment_notifications USING btree (is_read);


--
-- Name: idx_comment_notifications_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_comment_notifications_user_id ON public.comment_notifications USING btree (user_id);


--
-- Name: idx_comments_attachments; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_comments_attachments ON public.comments USING gin (attachments);


--
-- Name: idx_comments_author_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_comments_author_id ON public.comments USING btree (author_id);


--
-- Name: idx_comments_change_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_comments_change_id ON public.comments USING btree (change_id);


--
-- Name: idx_comments_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_comments_created_at ON public.comments USING btree (created_at);


--
-- Name: idx_comments_incident_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_comments_incident_id ON public.comments USING btree (incident_id);


--
-- Name: idx_comments_mentions; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_comments_mentions ON public.comments USING gin (mentions);


--
-- Name: idx_comments_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_comments_organization_id ON public.comments USING btree (organization_id);


--
-- Name: idx_comments_problem_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_comments_problem_id ON public.comments USING btree (problem_id);


--
-- Name: idx_grafana_integrations_enabled; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_grafana_integrations_enabled ON public.grafana_integrations USING btree (enabled);


--
-- Name: idx_grafana_integrations_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_grafana_integrations_organization_id ON public.grafana_integrations USING btree (organization_id);


--
-- Name: idx_incidents_attachments; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_incidents_attachments ON public.incidents USING gin (attachments);


--
-- Name: idx_incidents_customer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_incidents_customer ON public.incidents USING btree (customer);


--
-- Name: idx_incidents_links; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_incidents_links ON public.incidents USING gin (links);


--
-- Name: idx_incidents_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_incidents_organization_id ON public.incidents USING btree (organization_id);


--
-- Name: idx_incidents_problem_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_incidents_problem_id ON public.incidents USING btree (problem_id);


--
-- Name: idx_infrastructure_edges_env_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_infrastructure_edges_env_id ON public.infrastructure_edges USING btree (environment_id);


--
-- Name: idx_infrastructure_edges_org_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_infrastructure_edges_org_id ON public.infrastructure_edges USING btree (organization_id);


--
-- Name: idx_infrastructure_edges_source; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_infrastructure_edges_source ON public.infrastructure_edges USING btree (source);


--
-- Name: idx_infrastructure_edges_target; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_infrastructure_edges_target ON public.infrastructure_edges USING btree (target);


--
-- Name: idx_infrastructure_environments_org_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_infrastructure_environments_org_id ON public.infrastructure_environments USING btree (organization_id);


--
-- Name: idx_infrastructure_nodes_env_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_infrastructure_nodes_env_id ON public.infrastructure_nodes USING btree (environment_id);


--
-- Name: idx_infrastructure_nodes_org_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_infrastructure_nodes_org_id ON public.infrastructure_nodes USING btree (organization_id);


--
-- Name: idx_infrastructure_nodes_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_infrastructure_nodes_type ON public.infrastructure_nodes USING btree (type);


--
-- Name: idx_infrastructure_nodes_zone_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_infrastructure_nodes_zone_id ON public.infrastructure_nodes USING btree (zone_id);


--
-- Name: idx_infrastructure_zones_org_env; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_infrastructure_zones_org_env ON public.infrastructure_zones USING btree (organization_id, environment_id);


--
-- Name: idx_infrastructure_zones_parent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_infrastructure_zones_parent ON public.infrastructure_zones USING btree (parent_zone_id);


--
-- Name: idx_infrastructure_zones_path; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_infrastructure_zones_path ON public.infrastructure_zones USING gin (zone_path);


--
-- Name: idx_infrastructure_zones_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_infrastructure_zones_type ON public.infrastructure_zones USING btree (zone_type);


--
-- Name: idx_notifications_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notifications_organization_id ON public.notifications USING btree (organization_id);


--
-- Name: idx_notifications_read; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notifications_read ON public.notifications USING btree (read);


--
-- Name: idx_notifications_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notifications_type ON public.notifications USING btree (type);


--
-- Name: idx_notifications_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notifications_user_id ON public.notifications USING btree (user_id);


--
-- Name: idx_openai_usage_logs_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_openai_usage_logs_created_at ON public.openai_usage_logs USING btree (created_at);


--
-- Name: idx_openai_usage_logs_endpoint; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_openai_usage_logs_endpoint ON public.openai_usage_logs USING btree (endpoint);


--
-- Name: idx_openai_usage_logs_model; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_openai_usage_logs_model ON public.openai_usage_logs USING btree (model);


--
-- Name: idx_openai_usage_logs_org_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_openai_usage_logs_org_date ON public.openai_usage_logs USING btree (organization_id, created_at);


--
-- Name: idx_openai_usage_logs_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_openai_usage_logs_organization_id ON public.openai_usage_logs USING btree (organization_id);


--
-- Name: idx_organization_memberships_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_organization_memberships_organization_id ON public.organization_memberships USING btree (organization_id);


--
-- Name: idx_organization_memberships_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_organization_memberships_user_id ON public.organization_memberships USING btree (user_id);


--
-- Name: idx_pagerduty_integrations_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pagerduty_integrations_organization_id ON public.pagerduty_integrations USING btree (organization_id);


--
-- Name: idx_problems_attachments; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_problems_attachments ON public.problems USING gin (attachments);


--
-- Name: idx_problems_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_problems_organization_id ON public.problems USING btree (organization_id);


--
-- Name: idx_profiles_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_profiles_organization_id ON public.profiles USING btree (organization_id);


--
-- Name: idx_sla_configurations_org_priority; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sla_configurations_org_priority ON public.slo_configurations USING btree (organization_id, priority);


--
-- Name: changes change_before_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER change_before_insert BEFORE INSERT ON public.changes FOR EACH ROW EXECUTE FUNCTION public.handle_change_before_insert();


--
-- Name: comments create_mention_notifications_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER create_mention_notifications_trigger AFTER INSERT ON public.comments FOR EACH ROW EXECUTE FUNCTION public.create_mention_notifications();


--
-- Name: incidents incident_before_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER incident_before_insert BEFORE INSERT ON public.incidents FOR EACH ROW EXECUTE FUNCTION public.handle_incident_before_insert();


--
-- Name: incidents incident_before_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER incident_before_update BEFORE UPDATE ON public.incidents FOR EACH ROW EXECUTE FUNCTION public.handle_incident_before_update();


--
-- Name: problems problem_before_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER problem_before_insert BEFORE INSERT ON public.problems FOR EACH ROW EXECUTE FUNCTION public.handle_problem_before_insert();


--
-- Name: problems problem_before_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER problem_before_update BEFORE UPDATE ON public.problems FOR EACH ROW EXECUTE FUNCTION public.handle_problem_before_update();


--
-- Name: organizations trigger_set_billing_expiration; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_set_billing_expiration BEFORE INSERT ON public.organizations FOR EACH ROW EXECUTE FUNCTION public.set_billing_expiration();


--
-- Name: grafana_integrations trigger_update_grafana_integrations_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_update_grafana_integrations_updated_at BEFORE UPDATE ON public.grafana_integrations FOR EACH ROW EXECUTE FUNCTION public.update_grafana_integrations_updated_at();


--
-- Name: ai_scan_tokens update_ai_scan_tokens_updated_at_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_ai_scan_tokens_updated_at_trigger BEFORE UPDATE ON public.ai_scan_tokens FOR EACH ROW EXECUTE FUNCTION public.update_ai_scan_tokens_updated_at();


--
-- Name: api_tokens update_api_tokens_updated_at_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_api_tokens_updated_at_trigger BEFORE UPDATE ON public.api_tokens FOR EACH ROW EXECUTE FUNCTION public.update_api_tokens_updated_at();


--
-- Name: change_approvals update_change_approvals_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_change_approvals_updated_at BEFORE UPDATE ON public.change_approvals FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: change_automations update_change_automations_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_change_automations_updated_at BEFORE UPDATE ON public.change_automations FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: change_completion_responses update_change_completion_responses_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_change_completion_responses_updated_at BEFORE UPDATE ON public.change_completion_responses FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: comments update_comments_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_comments_updated_at BEFORE UPDATE ON public.comments FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: infrastructure_edges update_infrastructure_edges_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_infrastructure_edges_updated_at BEFORE UPDATE ON public.infrastructure_edges FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: infrastructure_environments update_infrastructure_environments_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_infrastructure_environments_updated_at BEFORE UPDATE ON public.infrastructure_environments FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: infrastructure_nodes update_infrastructure_nodes_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_infrastructure_nodes_updated_at BEFORE UPDATE ON public.infrastructure_nodes FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: notifications update_notifications_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_notifications_updated_at BEFORE UPDATE ON public.notifications FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: pagerduty_integrations update_pagerduty_integrations_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_pagerduty_integrations_updated_at BEFORE UPDATE ON public.pagerduty_integrations FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: slo_configurations update_sla_configurations_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_sla_configurations_updated_at BEFORE UPDATE ON public.slo_configurations FOR EACH ROW EXECUTE FUNCTION public.update_sla_configurations_updated_at();


--
-- Name: ai_cache ai_cache_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_cache
    ADD CONSTRAINT ai_cache_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: ai_scan_tokens ai_scan_tokens_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_scan_tokens
    ADD CONSTRAINT ai_scan_tokens_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: ai_scan_tokens ai_scan_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_scan_tokens
    ADD CONSTRAINT ai_scan_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: api_tokens api_tokens_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_tokens
    ADD CONSTRAINT api_tokens_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: api_tokens api_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_tokens
    ADD CONSTRAINT api_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: billing_integrations billing_integrations_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_integrations
    ADD CONSTRAINT billing_integrations_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: change_approvals change_approvals_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.change_approvals
    ADD CONSTRAINT change_approvals_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: change_approvals change_approvals_change_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.change_approvals
    ADD CONSTRAINT change_approvals_change_id_fkey FOREIGN KEY (change_id) REFERENCES public.changes(id) ON DELETE CASCADE;


--
-- Name: change_approvals change_approvals_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.change_approvals
    ADD CONSTRAINT change_approvals_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: change_approvals change_approvals_requested_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.change_approvals
    ADD CONSTRAINT change_approvals_requested_by_fkey FOREIGN KEY (requested_by) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: change_automations change_automations_change_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.change_automations
    ADD CONSTRAINT change_automations_change_id_fkey FOREIGN KEY (change_id) REFERENCES public.changes(id) ON DELETE CASCADE;


--
-- Name: change_automations change_automations_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.change_automations
    ADD CONSTRAINT change_automations_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: change_completion_responses change_completion_responses_change_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.change_completion_responses
    ADD CONSTRAINT change_completion_responses_change_id_fkey FOREIGN KEY (change_id) REFERENCES public.changes(id) ON DELETE CASCADE;


--
-- Name: change_completion_responses change_completion_responses_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.change_completion_responses
    ADD CONSTRAINT change_completion_responses_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: change_completion_responses change_completion_responses_responded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.change_completion_responses
    ADD CONSTRAINT change_completion_responses_responded_by_fkey FOREIGN KEY (responded_by) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: change_sequences change_sequences_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.change_sequences
    ADD CONSTRAINT change_sequences_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: changes changes_assigned_to_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.changes
    ADD CONSTRAINT changes_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES public.profiles(id);


--
-- Name: changes changes_incident_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.changes
    ADD CONSTRAINT changes_incident_id_fkey FOREIGN KEY (incident_id) REFERENCES public.incidents(id) ON DELETE SET NULL;


--
-- Name: changes changes_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.changes
    ADD CONSTRAINT changes_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: changes changes_problem_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.changes
    ADD CONSTRAINT changes_problem_id_fkey FOREIGN KEY (problem_id) REFERENCES public.problems(id) ON DELETE SET NULL;


--
-- Name: changes changes_requested_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.changes
    ADD CONSTRAINT changes_requested_by_fkey FOREIGN KEY (requested_by) REFERENCES public.profiles(id);


--
-- Name: comment_notifications comment_notifications_comment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comment_notifications
    ADD CONSTRAINT comment_notifications_comment_id_fkey FOREIGN KEY (comment_id) REFERENCES public.comments(id) ON DELETE CASCADE;


--
-- Name: comment_notifications comment_notifications_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comment_notifications
    ADD CONSTRAINT comment_notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: comments comments_author_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_author_id_fkey FOREIGN KEY (author_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: comments comments_change_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_change_id_fkey FOREIGN KEY (change_id) REFERENCES public.changes(id) ON DELETE CASCADE;


--
-- Name: comments comments_incident_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_incident_id_fkey FOREIGN KEY (incident_id) REFERENCES public.incidents(id) ON DELETE CASCADE;


--
-- Name: comments comments_problem_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_problem_id_fkey FOREIGN KEY (problem_id) REFERENCES public.problems(id) ON DELETE CASCADE;


--
-- Name: pagerduty_integrations fk_pagerduty_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pagerduty_integrations
    ADD CONSTRAINT fk_pagerduty_organization FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: grafana_integrations grafana_integrations_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grafana_integrations
    ADD CONSTRAINT grafana_integrations_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: incident_sequences incident_sequences_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.incident_sequences
    ADD CONSTRAINT incident_sequences_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: incidents incidents_assigned_to_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.incidents
    ADD CONSTRAINT incidents_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES public.profiles(id);


--
-- Name: incidents incidents_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.incidents
    ADD CONSTRAINT incidents_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id);


--
-- Name: incidents incidents_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.incidents
    ADD CONSTRAINT incidents_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: incidents incidents_problem_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.incidents
    ADD CONSTRAINT incidents_problem_id_fkey FOREIGN KEY (problem_id) REFERENCES public.problems(id);


--
-- Name: infrastructure_edges infrastructure_edges_environment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.infrastructure_edges
    ADD CONSTRAINT infrastructure_edges_environment_id_fkey FOREIGN KEY (environment_id) REFERENCES public.infrastructure_environments(id) ON DELETE CASCADE;


--
-- Name: infrastructure_edges infrastructure_edges_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.infrastructure_edges
    ADD CONSTRAINT infrastructure_edges_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: infrastructure_environments infrastructure_environments_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.infrastructure_environments
    ADD CONSTRAINT infrastructure_environments_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: infrastructure_nodes infrastructure_nodes_environment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.infrastructure_nodes
    ADD CONSTRAINT infrastructure_nodes_environment_id_fkey FOREIGN KEY (environment_id) REFERENCES public.infrastructure_environments(id) ON DELETE CASCADE;


--
-- Name: infrastructure_nodes infrastructure_nodes_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.infrastructure_nodes
    ADD CONSTRAINT infrastructure_nodes_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: infrastructure_nodes infrastructure_nodes_zone_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.infrastructure_nodes
    ADD CONSTRAINT infrastructure_nodes_zone_id_fkey FOREIGN KEY (zone_id) REFERENCES public.infrastructure_zones(id) ON DELETE SET NULL;


--
-- Name: infrastructure_zones infrastructure_zones_environment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.infrastructure_zones
    ADD CONSTRAINT infrastructure_zones_environment_id_fkey FOREIGN KEY (environment_id) REFERENCES public.infrastructure_environments(id) ON DELETE CASCADE;


--
-- Name: infrastructure_zones infrastructure_zones_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.infrastructure_zones
    ADD CONSTRAINT infrastructure_zones_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: infrastructure_zones infrastructure_zones_parent_zone_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.infrastructure_zones
    ADD CONSTRAINT infrastructure_zones_parent_zone_id_fkey FOREIGN KEY (parent_zone_id) REFERENCES public.infrastructure_zones(id) ON DELETE CASCADE;


--
-- Name: notifications notifications_change_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_change_id_fkey FOREIGN KEY (change_id) REFERENCES public.changes(id) ON DELETE CASCADE;


--
-- Name: notifications notifications_incident_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_incident_id_fkey FOREIGN KEY (incident_id) REFERENCES public.incidents(id) ON DELETE CASCADE;


--
-- Name: notifications notifications_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: notifications notifications_problem_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_problem_id_fkey FOREIGN KEY (problem_id) REFERENCES public.problems(id) ON DELETE CASCADE;


--
-- Name: notifications notifications_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: openai_usage_logs openai_usage_logs_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.openai_usage_logs
    ADD CONSTRAINT openai_usage_logs_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: organization_memberships organization_memberships_invited_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_memberships
    ADD CONSTRAINT organization_memberships_invited_by_fkey FOREIGN KEY (invited_by) REFERENCES public.profiles(id);


--
-- Name: organization_memberships organization_memberships_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_memberships
    ADD CONSTRAINT organization_memberships_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: organization_memberships organization_memberships_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_memberships
    ADD CONSTRAINT organization_memberships_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: problem_sequences problem_sequences_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.problem_sequences
    ADD CONSTRAINT problem_sequences_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: problems problems_assigned_to_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.problems
    ADD CONSTRAINT problems_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES public.profiles(id);


--
-- Name: problems problems_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.problems
    ADD CONSTRAINT problems_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id);


--
-- Name: problems problems_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.problems
    ADD CONSTRAINT problems_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: profiles profiles_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: profiles profiles_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: slo_configurations sla_configurations_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.slo_configurations
    ADD CONSTRAINT sla_configurations_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: team_invitations team_invitations_invited_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_invitations
    ADD CONSTRAINT team_invitations_invited_by_fkey FOREIGN KEY (invited_by) REFERENCES public.profiles(id);


--
-- Name: team_invitations team_invitations_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_invitations
    ADD CONSTRAINT team_invitations_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: comment_notifications Allow authenticated users to create comment notifications; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow authenticated users to create comment notifications" ON public.comment_notifications FOR INSERT WITH CHECK ((auth.uid() IS NOT NULL));


--
-- Name: comment_notifications Allow system to create comment notifications; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow system to create comment notifications" ON public.comment_notifications FOR INSERT WITH CHECK (true);


--
-- Name: change_completion_responses Assigned users can respond to their changes; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Assigned users can respond to their changes" ON public.change_completion_responses FOR INSERT WITH CHECK (((auth.uid() = responded_by) AND (organization_id = public.get_user_organization_id()) AND (EXISTS ( SELECT 1
   FROM public.changes
  WHERE ((changes.id = change_completion_responses.change_id) AND (changes.assigned_to = auth.uid()))))));


--
-- Name: changes Authenticated users can insert changes in their organization; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Authenticated users can insert changes in their organization" ON public.changes FOR INSERT WITH CHECK (((auth.uid() = requested_by) AND (organization_id = public.get_user_organization_id())));


--
-- Name: incidents Authenticated users can insert incidents in their organization; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Authenticated users can insert incidents in their organization" ON public.incidents FOR INSERT WITH CHECK (((auth.uid() = created_by) AND (organization_id = public.get_user_organization_id())));


--
-- Name: problems Authenticated users can insert problems in their organization; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Authenticated users can insert problems in their organization" ON public.problems FOR INSERT WITH CHECK (((auth.uid() = created_by) AND (organization_id = public.get_user_organization_id())));


--
-- Name: change_approvals Managers can approve changes in their organization; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Managers can approve changes in their organization" ON public.change_approvals FOR UPDATE USING ((public.user_has_org_access(organization_id) AND (EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.organization_id = change_approvals.organization_id) AND (profiles.role = ANY (ARRAY['owner'::public.user_role_type, 'admin'::public.user_role_type, 'manager'::public.user_role_type])))))));


--
-- Name: slo_configurations Organization members can manage SLA configurations; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Organization members can manage SLA configurations" ON public.slo_configurations TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.organization_id = slo_configurations.organization_id)))));


--
-- Name: organizations Organization owners/admins can update their organization; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Organization owners/admins can update their organization" ON public.organizations FOR UPDATE USING (((id = public.get_user_organization_id()) AND (EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.organization_id = organizations.id) AND (profiles.role = ANY (ARRAY['owner'::public.user_role_type, 'admin'::public.user_role_type])))))));


--
-- Name: openai_usage_logs System can insert OpenAI usage logs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "System can insert OpenAI usage logs" ON public.openai_usage_logs FOR INSERT WITH CHECK (true);


--
-- Name: notifications System can insert notifications; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "System can insert notifications" ON public.notifications FOR INSERT WITH CHECK (public.user_has_org_access(organization_id));


--
-- Name: change_automations System can manage automations; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "System can manage automations" ON public.change_automations USING (public.user_has_org_access(organization_id));


--
-- Name: ai_cache Users can access their organization's AI cache; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can access their organization's AI cache" ON public.ai_cache USING ((organization_id IN ( SELECT om.organization_id
   FROM public.organization_memberships om
  WHERE (om.user_id = auth.uid()))));


--
-- Name: ai_scan_tokens Users can create own ai scan tokens; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can create own ai scan tokens" ON public.ai_scan_tokens FOR INSERT WITH CHECK ((auth.uid() = user_id));


--
-- Name: api_tokens Users can create own api tokens; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can create own api tokens" ON public.api_tokens FOR INSERT WITH CHECK ((auth.uid() = user_id));


--
-- Name: infrastructure_environments Users can delete environments for their organization; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can delete environments for their organization" ON public.infrastructure_environments FOR DELETE USING ((organization_id IN ( SELECT organization_memberships.organization_id
   FROM public.organization_memberships
  WHERE ((organization_memberships.user_id = auth.uid()) AND (organization_memberships.role = ANY (ARRAY['owner'::public.user_role_type, 'admin'::public.user_role_type, 'manager'::public.user_role_type]))))));


--
-- Name: infrastructure_edges Users can delete infrastructure edges for their organization; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can delete infrastructure edges for their organization" ON public.infrastructure_edges FOR DELETE USING ((organization_id IN ( SELECT organization_memberships.organization_id
   FROM public.organization_memberships
  WHERE ((organization_memberships.user_id = auth.uid()) AND (organization_memberships.role = ANY (ARRAY['owner'::public.user_role_type, 'admin'::public.user_role_type, 'manager'::public.user_role_type]))))));


--
-- Name: infrastructure_nodes Users can delete infrastructure nodes for their organization; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can delete infrastructure nodes for their organization" ON public.infrastructure_nodes FOR DELETE USING ((organization_id IN ( SELECT organization_memberships.organization_id
   FROM public.organization_memberships
  WHERE ((organization_memberships.user_id = auth.uid()) AND (organization_memberships.role = ANY (ARRAY['owner'::public.user_role_type, 'admin'::public.user_role_type, 'manager'::public.user_role_type]))))));


--
-- Name: api_tokens Users can delete own api tokens; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can delete own api tokens" ON public.api_tokens FOR DELETE USING ((auth.uid() = user_id));


--
-- Name: comments Users can delete their own comments; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can delete their own comments" ON public.comments FOR DELETE USING (((author_id = auth.uid()) AND (organization_id = ( SELECT profiles.organization_id
   FROM public.profiles
  WHERE (profiles.id = auth.uid())
 LIMIT 1))));


--
-- Name: infrastructure_zones Users can delete zones for their organization; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can delete zones for their organization" ON public.infrastructure_zones FOR DELETE USING ((organization_id IN ( SELECT organization_memberships.organization_id
   FROM public.organization_memberships
  WHERE ((organization_memberships.user_id = auth.uid()) AND (organization_memberships.role = ANY (ARRAY['owner'::public.user_role_type, 'admin'::public.user_role_type, 'manager'::public.user_role_type]))))));


--
-- Name: comments Users can insert comments for their organization; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can insert comments for their organization" ON public.comments FOR INSERT WITH CHECK (((author_id = auth.uid()) AND (organization_id = ( SELECT profiles.organization_id
   FROM public.profiles
  WHERE (profiles.id = auth.uid())
 LIMIT 1))));


--
-- Name: infrastructure_environments Users can insert environments for their organization; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can insert environments for their organization" ON public.infrastructure_environments FOR INSERT WITH CHECK ((organization_id IN ( SELECT organization_memberships.organization_id
   FROM public.organization_memberships
  WHERE ((organization_memberships.user_id = auth.uid()) AND (organization_memberships.role = ANY (ARRAY['owner'::public.user_role_type, 'admin'::public.user_role_type, 'manager'::public.user_role_type, 'member'::public.user_role_type]))))));


--
-- Name: infrastructure_edges Users can insert infrastructure edges for their organization; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can insert infrastructure edges for their organization" ON public.infrastructure_edges FOR INSERT WITH CHECK ((organization_id IN ( SELECT organization_memberships.organization_id
   FROM public.organization_memberships
  WHERE ((organization_memberships.user_id = auth.uid()) AND (organization_memberships.role = ANY (ARRAY['owner'::public.user_role_type, 'admin'::public.user_role_type, 'manager'::public.user_role_type, 'member'::public.user_role_type]))))));


--
-- Name: infrastructure_nodes Users can insert infrastructure nodes for their organization; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can insert infrastructure nodes for their organization" ON public.infrastructure_nodes FOR INSERT WITH CHECK ((organization_id IN ( SELECT organization_memberships.organization_id
   FROM public.organization_memberships
  WHERE ((organization_memberships.user_id = auth.uid()) AND (organization_memberships.role = ANY (ARRAY['owner'::public.user_role_type, 'admin'::public.user_role_type, 'manager'::public.user_role_type, 'member'::public.user_role_type]))))));


--
-- Name: profiles Users can insert their own profile; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can insert their own profile" ON public.profiles FOR INSERT WITH CHECK ((auth.uid() = id));


--
-- Name: infrastructure_zones Users can insert zones for their organization; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can insert zones for their organization" ON public.infrastructure_zones FOR INSERT WITH CHECK ((organization_id IN ( SELECT organization_memberships.organization_id
   FROM public.organization_memberships
  WHERE ((organization_memberships.user_id = auth.uid()) AND (organization_memberships.role = ANY (ARRAY['owner'::public.user_role_type, 'admin'::public.user_role_type, 'manager'::public.user_role_type, 'member'::public.user_role_type]))))));


--
-- Name: pagerduty_integrations Users can manage their organization's PagerDuty integration; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can manage their organization's PagerDuty integration" ON public.pagerduty_integrations USING ((organization_id = ( SELECT profiles.organization_id
   FROM public.profiles
  WHERE (profiles.id = auth.uid()))));


--
-- Name: comment_notifications Users can read their own comment notifications; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can read their own comment notifications" ON public.comment_notifications FOR SELECT USING ((user_id = auth.uid()));


--
-- Name: change_approvals Users can request approvals in their organization; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can request approvals in their organization" ON public.change_approvals FOR INSERT WITH CHECK (((auth.uid() = requested_by) AND (organization_id = public.get_user_organization_id())));


--
-- Name: changes Users can update changes in their organization; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update changes in their organization" ON public.changes FOR UPDATE USING ((public.user_has_org_access(organization_id) AND ((auth.uid() = requested_by) OR (auth.uid() = assigned_to))));


--
-- Name: infrastructure_environments Users can update environments for their organization; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update environments for their organization" ON public.infrastructure_environments FOR UPDATE USING ((organization_id IN ( SELECT organization_memberships.organization_id
   FROM public.organization_memberships
  WHERE ((organization_memberships.user_id = auth.uid()) AND (organization_memberships.role = ANY (ARRAY['owner'::public.user_role_type, 'admin'::public.user_role_type, 'manager'::public.user_role_type, 'member'::public.user_role_type]))))));


--
-- Name: incidents Users can update incidents in their organization; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update incidents in their organization" ON public.incidents FOR UPDATE USING ((public.user_has_org_access(organization_id) AND ((auth.uid() = created_by) OR (auth.uid() = assigned_to))));


--
-- Name: infrastructure_edges Users can update infrastructure edges for their organization; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update infrastructure edges for their organization" ON public.infrastructure_edges FOR UPDATE USING ((organization_id IN ( SELECT organization_memberships.organization_id
   FROM public.organization_memberships
  WHERE ((organization_memberships.user_id = auth.uid()) AND (organization_memberships.role = ANY (ARRAY['owner'::public.user_role_type, 'admin'::public.user_role_type, 'manager'::public.user_role_type, 'member'::public.user_role_type]))))));


--
-- Name: infrastructure_nodes Users can update infrastructure nodes for their organization; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update infrastructure nodes for their organization" ON public.infrastructure_nodes FOR UPDATE USING ((organization_id IN ( SELECT organization_memberships.organization_id
   FROM public.organization_memberships
  WHERE ((organization_memberships.user_id = auth.uid()) AND (organization_memberships.role = ANY (ARRAY['owner'::public.user_role_type, 'admin'::public.user_role_type, 'manager'::public.user_role_type, 'member'::public.user_role_type]))))));


--
-- Name: ai_scan_tokens Users can update own ai scan tokens; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update own ai scan tokens" ON public.ai_scan_tokens FOR UPDATE USING ((auth.uid() = user_id));


--
-- Name: api_tokens Users can update own api tokens; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update own api tokens" ON public.api_tokens FOR UPDATE USING ((auth.uid() = user_id));


--
-- Name: problems Users can update problems in their organization; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update problems in their organization" ON public.problems FOR UPDATE USING ((public.user_has_org_access(organization_id) AND ((auth.uid() = created_by) OR (auth.uid() = assigned_to))));


--
-- Name: comment_notifications Users can update their own comment notifications; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update their own comment notifications" ON public.comment_notifications FOR UPDATE USING ((user_id = auth.uid()));


--
-- Name: comments Users can update their own comments; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update their own comments" ON public.comments FOR UPDATE USING (((author_id = auth.uid()) AND (organization_id = ( SELECT profiles.organization_id
   FROM public.profiles
  WHERE (profiles.id = auth.uid())
 LIMIT 1)))) WITH CHECK (((author_id = auth.uid()) AND (organization_id = ( SELECT profiles.organization_id
   FROM public.profiles
  WHERE (profiles.id = auth.uid())
 LIMIT 1))));


--
-- Name: comment_notifications Users can update their own notifications; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update their own notifications" ON public.comment_notifications FOR UPDATE USING ((user_id = auth.uid())) WITH CHECK ((user_id = auth.uid()));


--
-- Name: notifications Users can update their own notifications; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update their own notifications" ON public.notifications FOR UPDATE USING (((auth.uid() = user_id) AND public.user_has_org_access(organization_id)));


--
-- Name: profiles Users can update their own profile; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update their own profile" ON public.profiles FOR UPDATE USING ((auth.uid() = id));


--
-- Name: infrastructure_zones Users can update zones for their organization; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update zones for their organization" ON public.infrastructure_zones FOR UPDATE USING ((organization_id IN ( SELECT organization_memberships.organization_id
   FROM public.organization_memberships
  WHERE ((organization_memberships.user_id = auth.uid()) AND (organization_memberships.role = ANY (ARRAY['owner'::public.user_role_type, 'admin'::public.user_role_type, 'manager'::public.user_role_type, 'member'::public.user_role_type]))))));


--
-- Name: change_approvals Users can view approvals in their organization; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view approvals in their organization" ON public.change_approvals FOR SELECT USING (public.user_has_org_access(organization_id));


--
-- Name: change_automations Users can view automations in their organization; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view automations in their organization" ON public.change_automations FOR SELECT USING (public.user_has_org_access(organization_id));


--
-- Name: changes Users can view changes in their organization; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view changes in their organization" ON public.changes FOR SELECT USING (public.user_has_org_access(organization_id));


--
-- Name: comments Users can view comments from their organization; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view comments from their organization" ON public.comments FOR SELECT USING ((organization_id = ( SELECT profiles.organization_id
   FROM public.profiles
  WHERE (profiles.id = auth.uid())
 LIMIT 1)));


--
-- Name: change_completion_responses Users can view completion responses in their organization; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view completion responses in their organization" ON public.change_completion_responses FOR SELECT USING (public.user_has_org_access(organization_id));


--
-- Name: infrastructure_environments Users can view environments for their organization; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view environments for their organization" ON public.infrastructure_environments FOR SELECT USING ((organization_id IN ( SELECT organization_memberships.organization_id
   FROM public.organization_memberships
  WHERE (organization_memberships.user_id = auth.uid()))));


--
-- Name: incidents Users can view incidents in their organization; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view incidents in their organization" ON public.incidents FOR SELECT USING ((organization_id IN ( SELECT profiles.organization_id
   FROM public.profiles
  WHERE (profiles.id = auth.uid()))));


--
-- Name: infrastructure_edges Users can view infrastructure edges for their organization; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view infrastructure edges for their organization" ON public.infrastructure_edges FOR SELECT USING ((organization_id IN ( SELECT organization_memberships.organization_id
   FROM public.organization_memberships
  WHERE (organization_memberships.user_id = auth.uid()))));


--
-- Name: infrastructure_nodes Users can view infrastructure nodes for their organization; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view infrastructure nodes for their organization" ON public.infrastructure_nodes FOR SELECT USING ((organization_id IN ( SELECT organization_memberships.organization_id
   FROM public.organization_memberships
  WHERE (organization_memberships.user_id = auth.uid()))));


--
-- Name: organization_memberships Users can view memberships in their organization; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view memberships in their organization" ON public.organization_memberships FOR SELECT USING ((organization_id = public.get_user_organization_id()));


--
-- Name: ai_scan_tokens Users can view own ai scan tokens; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view own ai scan tokens" ON public.ai_scan_tokens FOR SELECT USING ((auth.uid() = user_id));


--
-- Name: api_tokens Users can view own api tokens; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view own api tokens" ON public.api_tokens FOR SELECT USING ((auth.uid() = user_id));


--
-- Name: problems Users can view problems in their organization; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view problems in their organization" ON public.problems FOR SELECT USING ((organization_id IN ( SELECT profiles.organization_id
   FROM public.profiles
  WHERE (profiles.id = auth.uid()))));


--
-- Name: profiles Users can view profiles in their organization; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view profiles in their organization" ON public.profiles FOR SELECT USING (((organization_id = public.get_user_organization_id()) OR (id = auth.uid())));


--
-- Name: openai_usage_logs Users can view their organization's OpenAI usage logs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view their organization's OpenAI usage logs" ON public.openai_usage_logs FOR SELECT USING ((organization_id IN ( SELECT om.organization_id
   FROM public.organization_memberships om
  WHERE (om.user_id = auth.uid()))));


--
-- Name: pagerduty_integrations Users can view their organization's PagerDuty integration; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view their organization's PagerDuty integration" ON public.pagerduty_integrations FOR SELECT USING ((organization_id = ( SELECT profiles.organization_id
   FROM public.profiles
  WHERE (profiles.id = auth.uid()))));


--
-- Name: comment_notifications Users can view their own notifications; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view their own notifications" ON public.comment_notifications FOR SELECT USING ((user_id = auth.uid()));


--
-- Name: notifications Users can view their own notifications; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view their own notifications" ON public.notifications FOR SELECT USING (((auth.uid() = user_id) AND public.user_has_org_access(organization_id)));


--
-- Name: organizations Users can view their own organization; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view their own organization" ON public.organizations FOR SELECT USING ((id = public.get_user_organization_id()));


--
-- Name: infrastructure_zones Users can view zones for their organization; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view zones for their organization" ON public.infrastructure_zones FOR SELECT USING ((organization_id IN ( SELECT organization_memberships.organization_id
   FROM public.organization_memberships
  WHERE (organization_memberships.user_id = auth.uid()))));


--
-- Name: ai_cache; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.ai_cache ENABLE ROW LEVEL SECURITY;

--
-- Name: ai_scan_tokens; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.ai_scan_tokens ENABLE ROW LEVEL SECURITY;

--
-- Name: api_tokens; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.api_tokens ENABLE ROW LEVEL SECURITY;

--
-- Name: billing_integrations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.billing_integrations ENABLE ROW LEVEL SECURITY;

--
-- Name: change_approvals; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.change_approvals ENABLE ROW LEVEL SECURITY;

--
-- Name: change_automations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.change_automations ENABLE ROW LEVEL SECURITY;

--
-- Name: change_completion_responses; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.change_completion_responses ENABLE ROW LEVEL SECURITY;

--
-- Name: changes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.changes ENABLE ROW LEVEL SECURITY;

--
-- Name: comment_notifications; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.comment_notifications ENABLE ROW LEVEL SECURITY;

--
-- Name: comments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.comments ENABLE ROW LEVEL SECURITY;

--
-- Name: grafana_integrations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.grafana_integrations ENABLE ROW LEVEL SECURITY;

--
-- Name: grafana_integrations grafana_integrations_delete_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY grafana_integrations_delete_policy ON public.grafana_integrations FOR DELETE USING ((organization_id IN ( SELECT profiles.organization_id
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = ANY (ARRAY['owner'::public.user_role_type, 'admin'::public.user_role_type, 'manager'::public.user_role_type]))))));


--
-- Name: grafana_integrations grafana_integrations_modify_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY grafana_integrations_modify_policy ON public.grafana_integrations FOR INSERT WITH CHECK ((organization_id IN ( SELECT profiles.organization_id
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = ANY (ARRAY['owner'::public.user_role_type, 'admin'::public.user_role_type, 'manager'::public.user_role_type]))))));


--
-- Name: grafana_integrations grafana_integrations_organization_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY grafana_integrations_organization_policy ON public.grafana_integrations USING ((organization_id IN ( SELECT profiles.organization_id
   FROM public.profiles
  WHERE (profiles.id = auth.uid()))));


--
-- Name: grafana_integrations grafana_integrations_update_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY grafana_integrations_update_policy ON public.grafana_integrations FOR UPDATE USING ((organization_id IN ( SELECT profiles.organization_id
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = ANY (ARRAY['owner'::public.user_role_type, 'admin'::public.user_role_type, 'manager'::public.user_role_type]))))));


--
-- Name: incidents; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.incidents ENABLE ROW LEVEL SECURITY;

--
-- Name: infrastructure_edges; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.infrastructure_edges ENABLE ROW LEVEL SECURITY;

--
-- Name: infrastructure_environments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.infrastructure_environments ENABLE ROW LEVEL SECURITY;

--
-- Name: infrastructure_nodes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.infrastructure_nodes ENABLE ROW LEVEL SECURITY;

--
-- Name: infrastructure_zones; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.infrastructure_zones ENABLE ROW LEVEL SECURITY;

--
-- Name: notifications; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

--
-- Name: openai_usage_logs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.openai_usage_logs ENABLE ROW LEVEL SECURITY;

--
-- Name: organization_memberships; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.organization_memberships ENABLE ROW LEVEL SECURITY;

--
-- Name: organizations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;

--
-- Name: pagerduty_integrations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.pagerduty_integrations ENABLE ROW LEVEL SECURITY;

--
-- Name: problems; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.problems ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

--
-- Name: slo_configurations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.slo_configurations ENABLE ROW LEVEL SECURITY;


-- ============================================================================
-- Applied migrations (baked in so fresh installs are secure on day one)
--
-- Source of truth: supabase/migrations/. Anything below this line is the
-- exact contents of every numbered migration we have shipped, in order. If
-- you are running this file on a brand-new database you do NOT need to apply
-- anything from supabase/migrations/ separately.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0001_security_hardening.sql
-- ---------------------------------------------------------------------------

BEGIN;

-- 1. SECURITY DEFINER search_path lockdown
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

-- 2. RLS — enable + policies on the 5 unprotected tables
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

-- 3. CHECK constraints on enum-like text columns
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

-- 4. updated_at triggers
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

-- 5. Indexes on hot filter / FK columns
CREATE INDEX IF NOT EXISTS idx_incidents_status                ON public.incidents (status);
CREATE INDEX IF NOT EXISTS idx_incidents_created_by            ON public.incidents (created_by);
CREATE INDEX IF NOT EXISTS idx_incidents_assigned_to           ON public.incidents (assigned_to)
  WHERE assigned_to IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_incidents_org_status            ON public.incidents (organization_id, status);
CREATE INDEX IF NOT EXISTS idx_incidents_org_created_at        ON public.incidents (organization_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_changes_status                  ON public.changes (status);
CREATE INDEX IF NOT EXISTS idx_changes_requested_by            ON public.changes (requested_by);
CREATE INDEX IF NOT EXISTS idx_changes_assigned_to             ON public.changes (assigned_to)
  WHERE assigned_to IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_changes_org_status              ON public.changes (organization_id, status);
CREATE INDEX IF NOT EXISTS idx_changes_org_scheduled_for       ON public.changes (organization_id, scheduled_for)
  WHERE scheduled_for IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_problems_status                 ON public.problems (status);
CREATE INDEX IF NOT EXISTS idx_problems_created_by             ON public.problems (created_by);
CREATE INDEX IF NOT EXISTS idx_problems_assigned_to            ON public.problems (assigned_to)
  WHERE assigned_to IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_problems_org_status             ON public.problems (organization_id, status);

CREATE INDEX IF NOT EXISTS idx_team_invitations_organization   ON public.team_invitations (organization_id);
CREATE INDEX IF NOT EXISTS idx_team_invitations_email          ON public.team_invitations (email);
CREATE INDEX IF NOT EXISTS idx_team_invitations_status         ON public.team_invitations (status);
CREATE INDEX IF NOT EXISTS idx_team_invitations_expires_at     ON public.team_invitations (expires_at)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_comments_org_created_at         ON public.comments (organization_id, created_at DESC);

-- 6. team_invitations.organization_id NOT NULL
DO $hardening$
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
$hardening$;

COMMIT;


--
-- PostgreSQL database dump complete
--

