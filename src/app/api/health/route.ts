import { NextResponse } from "next/server";

// Liveness + readiness probe used by the Docker HEALTHCHECK and compose file.
//
// We deliberately keep this endpoint cheap:
//   - no DB round-trip (that would cascade the app into "unhealthy" every
//     time Postgres is briefly busy)
//   - no external calls (OpenAI, PagerDuty, Grafana)
//   - no authentication
//
// If you need a deeper readiness probe (e.g. "can I reach Postgres, Redis,
// and storage?"), add `/api/health/ready` instead and leave this one alone.

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

export function GET() {
  return NextResponse.json(
    {
      status: "ok",
      service: "antops",
      version: process.env.npm_package_version ?? "unknown",
      uptime_s: Math.round(process.uptime()),
      timestamp: new Date().toISOString(),
    },
    { status: 200 },
  );
}
