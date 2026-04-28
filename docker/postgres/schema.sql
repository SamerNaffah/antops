-- ANTOPS Self-Hosted Database Schema
-- Simplified single-tenant version without Supabase dependencies

-- ============================================================================
-- CUSTOM TYPES
-- ============================================================================

CREATE TYPE priority_type AS ENUM ('low', 'medium', 'high', 'critical');
CREATE TYPE incident_status_type AS ENUM ('open', 'investigating', 'resolved', 'closed');
CREATE TYPE change_status_type AS ENUM ('draft', 'pending', 'approved', 'in_progress', 'completed', 'failed', 'cancelled');
CREATE TYPE problem_status_type AS ENUM ('identified', 'investigating', 'known_error', 'resolved', 'closed');
CREATE TYPE user_role_type AS ENUM ('admin', 'user', 'viewer');
CREATE TYPE notification_type AS ENUM ('incident_created', 'incident_assigned', 'incident_updated', 'change_created', 'change_approved', 'change_rejected', 'problem_created', 'comment_created', 'mention');

-- ============================================================================
-- CORE TABLES
-- ============================================================================

-- Users table (replaces Supabase auth.users + profiles)
CREATE TABLE users (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  full_name TEXT,
  avatar_url TEXT,
  role user_role_type NOT NULL DEFAULT 'user',
  is_active BOOLEAN NOT NULL DEFAULT true,
  last_login_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Create index on email for fast lookups
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_role ON users(role);

-- ============================================================================
-- ITIL MANAGEMENT TABLES
-- ============================================================================

-- Problems table
CREATE TABLE problems (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  priority priority_type NOT NULL DEFAULT 'medium',
  status problem_status_type NOT NULL DEFAULT 'identified',
  assigned_to UUID REFERENCES users(id) ON DELETE SET NULL,
  created_by UUID REFERENCES users(id) ON DELETE SET NULL NOT NULL,
  root_cause TEXT,
  workaround TEXT,
  solution TEXT,
  tags TEXT[] DEFAULT '{}',
  affected_services TEXT[] DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
  resolved_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_problems_status ON problems(status);
CREATE INDEX idx_problems_priority ON problems(priority);
CREATE INDEX idx_problems_assigned_to ON problems(assigned_to);
CREATE INDEX idx_problems_created_by ON problems(created_by);
CREATE INDEX idx_problems_created_at ON problems(created_at DESC);

-- Incidents table
CREATE TABLE incidents (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  priority priority_type NOT NULL DEFAULT 'medium',
  status incident_status_type NOT NULL DEFAULT 'open',
  assigned_to UUID REFERENCES users(id) ON DELETE SET NULL,
  created_by UUID REFERENCES users(id) ON DELETE SET NULL NOT NULL,
  problem_id UUID REFERENCES problems(id) ON DELETE SET NULL,
  tags TEXT[] DEFAULT '{}',
  affected_services TEXT[] DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
  resolved_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_incidents_status ON incidents(status);
CREATE INDEX idx_incidents_priority ON incidents(priority);
CREATE INDEX idx_incidents_assigned_to ON incidents(assigned_to);
CREATE INDEX idx_incidents_created_by ON incidents(created_by);
CREATE INDEX idx_incidents_problem_id ON incidents(problem_id);
CREATE INDEX idx_incidents_created_at ON incidents(created_at DESC);

-- Changes table
CREATE TABLE changes (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  status change_status_type NOT NULL DEFAULT 'draft',
  priority priority_type NOT NULL DEFAULT 'medium',
  requested_by UUID REFERENCES users(id) ON DELETE SET NULL NOT NULL,
  assigned_to UUID REFERENCES users(id) ON DELETE SET NULL,
  scheduled_for TIMESTAMP WITH TIME ZONE,
  rollback_plan TEXT NOT NULL,
  test_plan TEXT NOT NULL,
  tags TEXT[] DEFAULT '{}',
  affected_services TEXT[] DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
  completed_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_changes_status ON changes(status);
CREATE INDEX idx_changes_priority ON changes(priority);
CREATE INDEX idx_changes_requested_by ON changes(requested_by);
CREATE INDEX idx_changes_assigned_to ON changes(assigned_to);
CREATE INDEX idx_changes_scheduled_for ON changes(scheduled_for);
CREATE INDEX idx_changes_created_at ON changes(created_at DESC);

-- ============================================================================
-- COLLABORATION TABLES
-- ============================================================================

-- Comments table
CREATE TABLE comments (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  content TEXT NOT NULL,
  author_id UUID REFERENCES users(id) ON DELETE SET NULL NOT NULL,
  incident_id UUID REFERENCES incidents(id) ON DELETE CASCADE,
  change_id UUID REFERENCES changes(id) ON DELETE CASCADE,
  problem_id UUID REFERENCES problems(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
  CONSTRAINT comments_reference_check CHECK (
    (incident_id IS NOT NULL AND change_id IS NULL AND problem_id IS NULL) OR
    (incident_id IS NULL AND change_id IS NOT NULL AND problem_id IS NULL) OR
    (incident_id IS NULL AND change_id IS NULL AND problem_id IS NOT NULL)
  )
);

CREATE INDEX idx_comments_author_id ON comments(author_id);
CREATE INDEX idx_comments_incident_id ON comments(incident_id);
CREATE INDEX idx_comments_change_id ON comments(change_id);
CREATE INDEX idx_comments_problem_id ON comments(problem_id);
CREATE INDEX idx_comments_created_at ON comments(created_at DESC);

-- Notifications table
CREATE TABLE notifications (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE NOT NULL,
  type notification_type NOT NULL,
  title TEXT NOT NULL,
  message TEXT,
  entity_type TEXT NOT NULL,
  entity_id UUID NOT NULL,
  is_read BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

CREATE INDEX idx_notifications_user_id ON notifications(user_id);
CREATE INDEX idx_notifications_is_read ON notifications(is_read);
CREATE INDEX idx_notifications_created_at ON notifications(created_at DESC);
CREATE INDEX idx_notifications_user_unread ON notifications(user_id, is_read) WHERE is_read = false;

-- ============================================================================
-- APPROVAL WORKFLOW TABLES
-- ============================================================================

-- Change approvals table
CREATE TABLE change_approvals (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  change_id UUID REFERENCES changes(id) ON DELETE CASCADE NOT NULL,
  approver_id UUID REFERENCES users(id) ON DELETE CASCADE NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('pending', 'approved', 'rejected')),
  comments TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

CREATE INDEX idx_change_approvals_change_id ON change_approvals(change_id);
CREATE INDEX idx_change_approvals_approver_id ON change_approvals(approver_id);
CREATE INDEX idx_change_approvals_status ON change_approvals(status);

-- ============================================================================
-- INFRASTRUCTURE MAPPING TABLES
-- ============================================================================

-- Infrastructure nodes (components in the system diagram)
CREATE TABLE infrastructure_nodes (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  label TEXT NOT NULL,
  type TEXT NOT NULL,
  position_x DOUBLE PRECISION NOT NULL DEFAULT 0,
  position_y DOUBLE PRECISION NOT NULL DEFAULT 0,
  data JSONB,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

CREATE INDEX idx_infrastructure_nodes_type ON infrastructure_nodes(type);

-- Infrastructure edges (connections between nodes)
CREATE TABLE infrastructure_edges (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  source_id UUID REFERENCES infrastructure_nodes(id) ON DELETE CASCADE NOT NULL,
  target_id UUID REFERENCES infrastructure_nodes(id) ON DELETE CASCADE NOT NULL,
  label TEXT,
  type TEXT NOT NULL DEFAULT 'default',
  data JSONB,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

CREATE INDEX idx_infrastructure_edges_source ON infrastructure_edges(source_id);
CREATE INDEX idx_infrastructure_edges_target ON infrastructure_edges(target_id);

-- ============================================================================
-- API & INTEGRATION TABLES
-- ============================================================================

-- API tokens for programmatic access
CREATE TABLE api_tokens (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE NOT NULL,
  name TEXT NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  last_used_at TIMESTAMP WITH TIME ZONE,
  expires_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

CREATE INDEX idx_api_tokens_user_id ON api_tokens(user_id);
CREATE INDEX idx_api_tokens_token_hash ON api_tokens(token_hash);

-- PagerDuty integration
CREATE TABLE pagerduty_integrations (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  service_id TEXT NOT NULL,
  service_name TEXT NOT NULL,
  integration_key TEXT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Grafana integration
CREATE TABLE grafana_integrations (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  alert_name TEXT NOT NULL,
  dashboard_url TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- ============================================================================
-- AI USAGE TRACKING
-- ============================================================================

-- OpenAI usage logs (or can be used for any AI provider)
CREATE TABLE ai_usage_logs (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  model TEXT NOT NULL,
  prompt_tokens INTEGER NOT NULL,
  completion_tokens INTEGER NOT NULL,
  total_tokens INTEGER NOT NULL,
  cost DECIMAL(10, 6),
  endpoint TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

CREATE INDEX idx_ai_usage_logs_user_id ON ai_usage_logs(user_id);
CREATE INDEX idx_ai_usage_logs_created_at ON ai_usage_logs(created_at DESC);
CREATE INDEX idx_ai_usage_logs_model ON ai_usage_logs(model);

-- ============================================================================
-- FILE ATTACHMENTS METADATA
-- ============================================================================

-- File attachments (actual files stored in MinIO)
CREATE TABLE attachments (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  filename TEXT NOT NULL,
  file_path TEXT NOT NULL,
  file_size INTEGER NOT NULL,
  mime_type TEXT NOT NULL,
  uploaded_by UUID REFERENCES users(id) ON DELETE SET NULL NOT NULL,
  incident_id UUID REFERENCES incidents(id) ON DELETE CASCADE,
  change_id UUID REFERENCES changes(id) ON DELETE CASCADE,
  problem_id UUID REFERENCES problems(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
  CONSTRAINT attachments_reference_check CHECK (
    (incident_id IS NOT NULL AND change_id IS NULL AND problem_id IS NULL) OR
    (incident_id IS NULL AND change_id IS NOT NULL AND problem_id IS NULL) OR
    (incident_id IS NULL AND change_id IS NULL AND problem_id IS NOT NULL)
  )
);

CREATE INDEX idx_attachments_uploaded_by ON attachments(uploaded_by);
CREATE INDEX idx_attachments_incident_id ON attachments(incident_id);
CREATE INDEX idx_attachments_change_id ON attachments(change_id);
CREATE INDEX idx_attachments_problem_id ON attachments(problem_id);

-- ============================================================================
-- FUNCTIONS & TRIGGERS
-- ============================================================================

-- Function to update updated_at timestamp automatically
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = timezone('utc'::text, now());
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply updated_at trigger to all relevant tables
CREATE TRIGGER update_users_updated_at
  BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_problems_updated_at
  BEFORE UPDATE ON problems
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_incidents_updated_at
  BEFORE UPDATE ON incidents
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_changes_updated_at
  BEFORE UPDATE ON changes
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_comments_updated_at
  BEFORE UPDATE ON comments
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_change_approvals_updated_at
  BEFORE UPDATE ON change_approvals
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_infrastructure_nodes_updated_at
  BEFORE UPDATE ON infrastructure_nodes
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_infrastructure_edges_updated_at
  BEFORE UPDATE ON infrastructure_edges
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_pagerduty_integrations_updated_at
  BEFORE UPDATE ON pagerduty_integrations
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_grafana_integrations_updated_at
  BEFORE UPDATE ON grafana_integrations
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- SEED DATA (Optional - creates default admin user)
-- ============================================================================

-- Create default admin user (password: admin123 - CHANGE THIS!)
-- Password hash is bcrypt hash of "admin123"
INSERT INTO users (email, password_hash, full_name, role)
VALUES (
  'admin@antops.local',
  '$2a$10$rYvPXqLZLZlZLXqLZLZLZu0yXyXyXyXyXyXyXyXyXyXyXyXyXyXy',
  'System Administrator',
  'admin'
);

-- Note: The above password hash is a placeholder.
-- In practice, you should generate a real bcrypt hash for your admin password.
-- Example with Node.js:
--   const bcrypt = require('bcrypt');
--   const hash = await bcrypt.hash('your-secure-password', 10);

COMMENT ON TABLE users IS 'Self-hosted user management (replaces Supabase Auth)';
COMMENT ON TABLE problems IS 'ITIL Problem Management';
COMMENT ON TABLE incidents IS 'ITIL Incident Management';
COMMENT ON TABLE changes IS 'ITIL Change Management';
COMMENT ON TABLE infrastructure_nodes IS 'Infrastructure topology nodes for visual mapping';
COMMENT ON TABLE infrastructure_edges IS 'Infrastructure topology connections';
COMMENT ON TABLE ai_usage_logs IS 'Track AI API usage and costs';
