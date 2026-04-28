# SaaS vs Self-Hosted Comparison

A detailed comparison between the current SaaS version and the self-hosted version of ANTOPS.

## Architecture Comparison

### SaaS Version (Current)

```
User Browser
     │
     ├─► Next.js App (Vercel)
     │        │
     │        ├─► Supabase (Database + Auth + Storage)
     │        ├─► OpenAI API (AI Features)
     │        ├─► Stripe (Payments)
     │        └─► Integrations (PagerDuty, Grafana)
```

### Self-Hosted Version

```
User Browser
     │
     ├─► Next.js App (Docker)
     │        │
     │        ├─► PostgreSQL (Docker) - Database
     │        ├─► MinIO (Docker) - File Storage
     │        ├─► Redis (Docker) - Caching
     │        ├─► OpenAI/Claude API - AI Features (Optional)
     │        └─► Integrations (PagerDuty, Grafana) (Optional)
```

## Feature Comparison

| Feature | SaaS Version | Self-Hosted Version |
|---------|-------------|---------------------|
| **Infrastructure** |
| Hosting | Vercel Cloud | Self-managed (Docker) |
| Database | Supabase (Managed) | PostgreSQL (Self-hosted) |
| File Storage | Supabase Storage | MinIO (S3-compatible) |
| Caching | None | Redis |
| **Authentication** |
| Auth Provider | Supabase Auth | NextAuth.js |
| Social Logins | Supported | Can be configured |
| MFA/2FA | Via Supabase | Requires implementation |
| Session Storage | Supabase | JWT + Redis |
| **Multi-Tenancy** |
| Organizations | Yes (unlimited) | No (single tenant) |
| Org Isolation | Row-Level Security | Not applicable |
| Team Management | Per organization | System-wide |
| **User Management** |
| User Roles | 5 levels (org-scoped) | 3 levels (system-wide) |
| Role Types | owner, admin, manager, member, viewer | admin, user, viewer |
| User Permissions | Per organization | System-wide |
| **Billing** |
| Payment Processing | Stripe | Not included |
| Subscriptions | Yes | No |
| Usage Tracking | Yes | Optional |
| **Core Features** |
| Incident Management | ✅ | ✅ |
| Problem Management | ✅ | ✅ |
| Change Management | ✅ | ✅ |
| Infrastructure Mapping | ✅ | ✅ |
| Real-time Collaboration | ✅ | ✅ |
| Comments & Mentions | ✅ | ✅ |
| Notifications | ✅ | ✅ |
| File Attachments | ✅ | ✅ |
| **AI Features** |
| AI Provider | OpenAI | OpenAI or Claude |
| Risk Analysis | ✅ | ✅ (if enabled) |
| Insights | ✅ | ✅ (if enabled) |
| Usage Tracking | ✅ | ✅ |
| Cost Tracking | ✅ | ✅ |
| **Integrations** |
| PagerDuty | ✅ | ✅ (optional) |
| Grafana | ✅ | ✅ (optional) |
| Webhooks | ✅ | ✅ |
| **Operations** |
| Backups | Automatic (Supabase) | Manual (your responsibility) |
| Updates | Automatic | Manual |
| Monitoring | Vercel/Supabase | Your monitoring |
| Scaling | Automatic | Manual |
| High Availability | Via providers | Your responsibility |
| **Cost Model** |
| Infrastructure | Included in SaaS price | Your infrastructure costs |
| Support | Included | Community/DIY |
| Updates | Automatic | Manual |

## Technical Details

### Database Differences

#### SaaS Version
```typescript
// Supabase client
const { data, error } = await supabase
  .from('incidents')
  .select('*')
  .eq('organization_id', orgId)
  .order('created_at', { ascending: false });
```

#### Self-Hosted Version
```typescript
// PostgreSQL client
const incidents = await db.queryMany(
  `SELECT * FROM incidents
   ORDER BY created_at DESC`
);
```

**Key Changes:**
- No `organization_id` filtering (single tenant)
- Direct SQL queries instead of query builder
- Manual connection pool management

### Authentication Differences

#### SaaS Version
```typescript
// Supabase Auth
const { data: { user } } = await supabase.auth.getUser();
```

#### Self-Hosted Version
```typescript
// NextAuth
const session = await getServerSession(authOptions);
const user = session?.user;
```

**Key Changes:**
- JWT-based sessions instead of Supabase tokens
- Manual password hashing with bcrypt
- Session stored in Redis or database

### Storage Differences

#### SaaS Version
```typescript
// Supabase Storage
const { data, error } = await supabase.storage
  .from('attachments')
  .upload(path, file);
```

#### Self-Hosted Version
```typescript
// MinIO
const result = await storage.uploadFile(
  fileBuffer,
  fileName,
  metadata
);
```

**Key Changes:**
- S3-compatible API instead of Supabase Storage
- Manual bucket management
- Presigned URLs for secure access

## Migration Effort

### Code Changes Required

| Area | Files Affected | Complexity | Estimated Time |
|------|---------------|------------|----------------|
| Database queries | ~50 files | Medium | 3-5 days |
| Authentication | ~30 files | Medium | 2-3 days |
| Storage/files | ~10 files | Low | 1-2 days |
| Remove org logic | ~60 files | High | 2-4 days |
| Remove billing | ~15 files | Low | 1 day |
| Testing | All | High | 2-3 days |
| **Total** | **~165 files** | **Mixed** | **12-20 days** |

### Database Schema Changes

#### Tables Removed
- `organizations` - No multi-tenancy
- `organization_members` - No multi-tenancy
- `billing_integrations` - No billing

#### Tables Modified
- `profiles` → `users` - Combined auth and profile
- All tables: Remove `organization_id` column
- All tables: Remove RLS policies

#### Tables Added
- None (schema simplified)

### Deployment Changes

#### SaaS Version
```bash
# Vercel deployment
git push origin main
# Automatic deployment via Vercel

# Environment variables in Vercel dashboard
# Supabase URL and keys configured
```

#### Self-Hosted Version
```bash
# Docker Compose deployment
docker-compose up -d

# Environment variables in .env file
# All services self-contained
```

## Advantages & Disadvantages

### Self-Hosted Advantages

✅ **Full Control**
- Complete control over infrastructure
- No dependency on third-party services
- Customize anything you want

✅ **Data Privacy**
- All data stays on your infrastructure
- No data sent to third parties
- Compliance with data residency requirements

✅ **Cost Predictability**
- No per-seat pricing
- No usage-based charges
- Pay only for infrastructure

✅ **Customization**
- Modify code freely
- Add custom features
- No SaaS limitations

✅ **No Vendor Lock-in**
- Own your data
- Migrate anytime
- No subscription dependencies

### Self-Hosted Disadvantages

❌ **Operational Burden**
- You manage infrastructure
- You handle backups
- You monitor services
- You apply security patches

❌ **Expertise Required**
- Need DevOps skills
- Database administration
- Security hardening
- Troubleshooting

❌ **Initial Setup Time**
- Longer to get started
- Configuration required
- Testing needed

❌ **Scaling Complexity**
- Manual scaling required
- Load balancing setup
- Database replication

❌ **No Automatic Updates**
- Manual upgrade process
- Testing required
- Downtime possible

## Cost Comparison

### SaaS Version (Hypothetical)

```
Monthly Costs:
- Base subscription: $99/month
- Per user: $15/user/month (for 10 users = $150)
- OpenAI API: ~$50/month
- Total: ~$299/month
```

### Self-Hosted Version

```
Monthly Costs:
- VPS (4 CPU, 8GB RAM): $40-80/month
- Storage (100GB): $10/month
- Backups (offsite): $10/month
- OpenAI API: ~$50/month
- Total: ~$110-150/month

One-time costs:
- Migration effort: 12-20 days of dev time
- Setup & testing: 3-5 days
```

**Break-even point**: ~6-12 months depending on:
- Number of users
- Usage patterns
- Infrastructure choices
- Existing DevOps capacity

## When to Choose Self-Hosted

### Good Fit For:

✅ **Compliance Requirements**
- Healthcare (HIPAA)
- Finance (PCI-DSS)
- Government
- Data residency laws

✅ **Cost Optimization**
- Large teams (>20 users)
- High usage volumes
- Long-term usage

✅ **Customization Needs**
- Custom features required
- Integration with internal systems
- Specific workflow requirements

✅ **Technical Capacity**
- In-house DevOps team
- Existing infrastructure
- Technical expertise available

### Not Recommended For:

❌ **Limited Resources**
- Small teams (<5 people)
- No DevOps expertise
- Limited budget

❌ **Quick Start Needed**
- Need to start immediately
- No time for setup
- Proof of concept

❌ **Managed Services Preferred**
- Want automatic updates
- Need 24/7 support
- Prefer predictable costs

## Migration Path

### Step-by-Step Transition

**Phase 1: Preparation** (1 week)
1. Review migration plan
2. Set up Docker environment
3. Test self-hosted infrastructure
4. Plan data migration

**Phase 2: Development** (2-3 weeks)
1. Migrate database layer
2. Implement authentication
3. Update API routes
4. Update client components
5. Test thoroughly

**Phase 3: Data Migration** (1 week)
1. Export data from Supabase
2. Transform to new schema
3. Import to self-hosted database
4. Verify data integrity

**Phase 4: Cutover** (3-5 days)
1. Final testing
2. User training
3. DNS/routing changes
4. Monitor closely

**Total Time**: 4-6 weeks for complete migration

## Conclusion

The self-hosted version provides **complete control and data privacy** at the cost of **operational complexity**.

**Choose self-hosted if:**
- You have DevOps expertise
- Data privacy is critical
- You want full customization
- Long-term cost savings are important

**Stay with SaaS if:**
- You want simplicity
- Quick start is important
- Managed services are preferred
- Small team with limited resources

Both versions maintain the same **core ITIL functionality** - the difference is in deployment, operations, and control.
