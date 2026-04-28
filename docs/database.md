# Database Schema Documentation

## Overview

ANTOPS uses PostgreSQL (via Supabase) with a complete schema defined in `complete-schema.sql`.

## Quick Setup

1. Create a new Supabase project at [supabase.com](https://supabase.com)
2. Open SQL Editor in your project
3. Copy the entire contents of `complete-schema.sql`
4. Paste and run in SQL Editor
5. Done! All tables, policies, and functions are created

## Database Structure

### Core ITIL Tables

**Incidents** (`incidents`)
- Track and manage incidents
- Status workflow: open → investigating → resolved → closed
- Priorities: low, medium, high, critical
- Can be linked to problems

**Problems** (`problems`)
- Root cause analysis
- Track workarounds and solutions
- Link multiple incidents to a problem
- Known error database

**Changes** (`changes`)
- Change request management
- Approval workflow
- Rollback and test plans
- Scheduling and tracking

### Organization & Team

**Organizations** (`organizations`)
- Multi-tenant structure
- Each organization is isolated

**Profiles** (`profiles`)
- User profiles linked to Supabase Auth
- Stores user metadata

**Organization Memberships** (`organization_memberships`)
- Links users to organizations
- Defines roles: owner, admin, manager, member, viewer

**Team Invitations** (`team_invitations`)
- Invite new team members
- Email-based invitations with tokens

### Infrastructure

**Infrastructure Nodes** (`infrastructure_nodes`)
- Components in your infrastructure
- Servers, databases, load balancers, etc.
- Visual diagram positions

**Infrastructure Edges** (`infrastructure_edges`)
- Connections between components
- Defines relationships and dependencies

**Infrastructure Zones** (`infrastructure_zones`)
- Group components by zone/region

**Infrastructure Environments** (`infrastructure_environments`)
- Production, staging, development, etc.

### Collaboration

**Comments** (`comments`)
- Comments on incidents, problems, changes
- Supports mentions and attachments
- Real-time updates via WebSocket

**Notifications** (`notifications`)
- System notifications
- Assignment alerts
- Mention notifications
- Status updates

**Comment Notifications** (`comment_notifications`)
- Notifications for comment activity

### AI Features

**AI Cache** (`ai_cache`)
- Cache AI analysis results
- Reduces API calls and costs

**OpenAI Usage Logs** (`openai_usage_logs`)
- Track API usage
- Monitor costs
- Token consumption

**AI Scan Tokens** (`ai_scan_tokens`)
- Rate limiting for AI features

### Integrations

**PagerDuty Integration** (`pagerduty_integrations`)
- Connect PagerDuty services
- Auto-create incidents from alerts

**Grafana Integration** (`grafana_integrations`)
- Webhook integration
- Alert monitoring

**Billing Integrations** (`billing_integrations`)
- Stripe integration
- Subscription management

### Approval & Automation

**Change Approvals** (`change_approvals`)
- Multi-step approval workflow
- Track approver decisions

**Change Automations** (`change_automations`)
- Automated change sequences
- Scheduled changes

**Change Completion Responses** (`change_completion_responses`)
- Track change execution results

### Utilities

**API Tokens** (`api_tokens`)
- Programmatic API access
- Token-based authentication

**Sequences** (Multiple)
- `incident_sequences` - Auto-increment incident IDs
- `problem_sequences` - Auto-increment problem IDs
- `change_sequences` - Auto-increment change IDs

**SLO Configurations** (`slo_configurations`)
- Service Level Objectives
- Response time targets

**Views**
- `user_organization_stats` - Aggregate user statistics

## Row Level Security (RLS)

All tables have RLS enabled to ensure:
- Users only see data from their organization
- Proper access control based on roles
- Data isolation between organizations

## Key Features

### Triggers
- Automatic `updated_at` timestamp updates
- Sequence number generation
- Notification creation

### Functions
- User authentication helpers
- Organization management
- Search and filtering

### Indexes
- Performance optimization on frequently queried columns
- Foreign key indexes
- Composite indexes for complex queries

## Schema Updates

The `complete-schema.sql` file is the **single source of truth** for the database schema.

When you need to update:
1. Make changes in your Supabase project
2. Export the updated schema
3. Replace `complete-schema.sql`
4. Commit to repository

## Export Current Schema

To export your current schema from Supabase:

```bash
# Using pg_dump
pg_dump "postgresql://postgres:[PASSWORD]@db.[PROJECT-REF].supabase.co:5432/postgres" \
  --schema=public \
  --schema-only \
  --no-owner \
  --no-privileges \
  > complete-schema.sql
```

Or use the Supabase Dashboard SQL Editor to run queries and export specific tables.

## Table Count

Total: **28 tables + 1 view**

## Size Estimate

- Empty schema: ~100KB
- With moderate data (1000 incidents): ~50-100MB
- Scales linearly with data volume

## Backup Recommendations

1. **Automated Backups**: Enable in Supabase project settings
2. **Point-in-Time Recovery**: Available on Pro plan
3. **Manual Exports**: Regular pg_dump exports
4. **File Storage**: Separate backup of Supabase Storage

## Support

For schema questions or issues:
- Check this documentation
- Review `complete-schema.sql`
- Open an issue on GitHub
- Email: samer.naffah@antopshq.com

---

**Schema Version**: 1.0.0
**Last Updated**: 2025-01-21
**Supabase Compatible**: Yes
