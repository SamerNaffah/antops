# Deployment Guide

## Overview

ANTOPS is **open source** but requires external services to run. This means the code is free and publicly available, but you'll need to set up your own accounts with third-party services.

## Required Services

### 1. Supabase (Database & Auth) - **Required**

**What it is:** PostgreSQL database + authentication service

**Cost:**
- Free tier: Up to 500MB database, 50,000 monthly active users
- Pro tier: $25/month for more resources
- [Pricing details](https://supabase.com/pricing)

**Setup:**
1. Create account at [supabase.com](https://supabase.com)
2. Create a new project
3. Run `complete-schema.sql` in SQL Editor
4. Copy your API keys to `.env.local`

**Why required:** ANTOPS uses Supabase for:
- PostgreSQL database storage
- User authentication
- Row Level Security (RLS)
- File storage
- Real-time subscriptions

### 2. OpenAI (AI Features) - **Optional**

**What it is:** AI-powered insights and analysis

**Cost:**
- Pay-per-use (typically $1-5/month for normal usage)
- [Pricing details](https://openai.com/pricing)

**Setup:**
1. Create account at [platform.openai.com](https://platform.openai.com)
2. Generate API key
3. Add to `.env.local`

**Why optional:** AI features enhance the platform but aren't required for core ITIL functionality

**What you miss without it:**
- Risk analysis
- Component insights
- Failure predictions
- AI-powered recommendations

## Deployment Options

### Option 1: Vercel (Recommended)

**Best for:** Quick deployment, automatic scaling

**Steps:**
1. Push code to GitHub
2. Import project in [Vercel](https://vercel.com)
3. Add environment variables
4. Deploy!

**Cost:**
- Hobby: Free (for personal projects)
- Pro: $20/month

**Note:** WebSocket features may require custom setup

### Option 2: Docker + VPS

**Best for:** Full control, custom infrastructure

**Requirements:**
- VPS (DigitalOcean, AWS, etc.)
- Docker installed
- Domain name (optional)

**Steps:**
1. Clone repository to VPS
2. Set up environment variables
3. Run `docker-compose up` (if Docker setup exists)
4. Configure reverse proxy (nginx/caddy)

**Cost:**
- VPS: $5-20/month depending on resources

### Option 3: Other Platforms

- **Railway**: Similar to Vercel, good for Node.js apps
- **Render**: Free tier available
- **Heroku**: Easy deployment but more expensive
- **AWS/GCP**: Maximum flexibility, higher complexity

## Self-Hosted Option

**Status:** Alpha — see [`self-hosting.md`](self-hosting.md) for the
Docker Compose path (Postgres + MinIO + Redis + the app). Stands up on a
single host without any SaaS account. Tracking the remaining
Supabase-vs-NextAuth ambiguity in `ANTOPS_AUDIT.md` §3.2.

## What's Included vs What You Need

### ✅ Included (Open Source)
- Complete application source code
- Database schema
- All features and functionality
- Documentation
- MIT License

### 🔑 You Need to Provide
- Supabase account & database
- Server/hosting (Vercel, VPS, etc.)
- Domain name (optional)
- SSL certificate (Let's Encrypt is free)
- OpenAI API key (optional, for AI features)

## Cost Estimate

**Minimal Setup (Free Tier):**
- Supabase: Free (up to limits)
- Vercel: Free (hobby tier)
- Domain: ~$12/year (optional)
- **Total: ~$0-1/month** (plus domain)

**Production Setup:**
- Supabase Pro: $25/month
- Vercel Pro: $20/month
- OpenAI: ~$5/month (typical usage)
- Domain + SSL: ~$12/year
- **Total: ~$50/month**

**Self-Hosted Alternative (if implemented):**
- VPS (4GB RAM): $20/month
- PostgreSQL: Self-hosted (included)
- MinIO: Self-hosted (included)
- Domain + SSL: ~$12/year
- OpenAI: ~$5/month
- **Total: ~$25-30/month** (more work to maintain)

## Data Ownership

### Current (Open Source with Supabase)
- Your data: Stored in **your own Supabase project**
- You control: Database access, backups, exports
- Supabase can: Access your data (per their terms)
- You can: Export and migrate anytime

### Future (Self-Hosted)
- Your data: Stored on **your own servers**
- You control: Everything
- No third party: Has access to your data
- Maximum privacy: Complete data sovereignty

## Comparison

| Feature | Open Source (Current) | Self-Hosted (Future) |
|---------|----------------------|---------------------|
| Setup Time | 30 minutes | 2-3 hours |
| Maintenance | Low | High |
| Cost (small scale) | $0-25/month | $25-30/month |
| Cost (large scale) | $50-100/month | $30-50/month |
| Technical Skill | Basic | Advanced |
| Data Control | High | Maximum |
| Update Complexity | Easy (git pull) | Medium |
| Scaling | Automatic | Manual |

## Recommended For

### Use Open Source (Current) If:
- ✅ You want quick setup
- ✅ You're okay with Supabase
- ✅ You want automatic scaling
- ✅ You prefer managed services
- ✅ Small to medium team

### Wait for Self-Hosted If:
- ✅ Maximum data control required
- ✅ Compliance requirements (HIPAA, etc.)
- ✅ High volume (1000+ users)
- ✅ Existing infrastructure to leverage
- ✅ In-house DevOps team

## Getting Started

1. **Choose your path:** Open source deployment (ready now)
2. **Set up Supabase:** Create project and run schema
3. **Deploy application:** Vercel, VPS, or other platform
4. **Configure integrations:** OpenAI (optional)
5. **Invite your team:** Start using ANTOPS!

## Support

- **Documentation:** This file, README.md, DATABASE.md
- **Issues:** [GitHub Issues](https://github.com/SamerNaffah/antops/issues)
- **Discussions:** [GitHub Discussions](https://github.com/SamerNaffah/antops/discussions)
- **Email:** naffahsamer@gmail.com

## Future Plans

Self-hosted deployment is on the roadmap. If you're interested:
- ⭐ Star the repository
- 👀 Watch for updates
- 💬 Join discussions about self-hosting
- 🤝 Contribute if you want to help implement it

---

**ANTOPS is open source, not self-hosted (yet).**

You own the code, but you'll need third-party services to run it.
