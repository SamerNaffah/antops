# Multi-stage Dockerfile for the Antops self-hosted image.
#
# Build:    docker build -t antops:local .
# Run:      docker compose up -d
#
# The image is built FROM Node 20 Alpine. Stage 1 installs deps, stage 2
# builds the Next.js app (which emits .next/standalone thanks to
# `output: "standalone"` in next.config.ts), stage 3 produces a slim runner
# that runs as a non-root user.

# ---------------------------------------------------------------------------
# Stage 1: deps
# ---------------------------------------------------------------------------
FROM node:20-alpine AS deps
RUN apk add --no-cache libc6-compat
WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm ci

# ---------------------------------------------------------------------------
# Stage 2: builder
# ---------------------------------------------------------------------------
FROM node:20-alpine AS builder
WORKDIR /app

ENV NEXT_TELEMETRY_DISABLED=1
ENV NODE_ENV=production

COPY --from=deps /app/node_modules ./node_modules
COPY . .

RUN npm run build

# ---------------------------------------------------------------------------
# Stage 3: runner
# ---------------------------------------------------------------------------
FROM node:20-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV PORT=3000
ENV HOSTNAME=0.0.0.0

# Non-root user
RUN addgroup --system --gid 1001 nodejs \
 && adduser  --system --uid 1001 nextjs

# Standalone build output + static assets
COPY --from=builder /app/public            ./public
COPY --from=builder /app/.next/standalone  ./
COPY --from=builder /app/.next/static      ./.next/static

# Custom server (Next.js + Socket.io). Standalone bundle does NOT include
# server.js, so we copy it explicitly. The bundle's own node_modules also
# doesn't include all of our runtime deps, so we copy the full ones.
COPY --from=builder /app/server.js     ./server.js
COPY --from=builder /app/node_modules  ./node_modules

RUN chown -R nextjs:nodejs /app

USER nextjs

EXPOSE 3000

# Container-level healthcheck (compose defines its own as well; both probe
# the same endpoint).
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://localhost:3000/api/health || exit 1

CMD ["node", "server.js"]
