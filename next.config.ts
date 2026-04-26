import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Required for the Docker image. `next build` emits `.next/standalone/`,
  // which the Dockerfile copies into the runner stage.
  // Docs: https://nextjs.org/docs/app/api-reference/next-config-js/output
  output: "standalone",

  // Emit React in strict mode to surface unsafe lifecycle bugs early.
  reactStrictMode: true,

  eslint: {
    // TODO(week-2): flip to `false` and fix violations. Keeping `true` today
    // because parts of src/components (notably InfrastructureView.tsx) carry
    // pre-existing `any`/unused-import errors that would break CI on flip.
    // Tracked in ANTOPS_AUDIT.md §1.2.
    ignoreDuringBuilds: true,
  },
};

export default nextConfig;
