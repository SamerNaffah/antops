/*
 * Custom Next.js server.
 *
 * Why a custom server instead of `next start`?
 *   We need a single HTTP server that both serves Next.js pages and hosts
 *   the Socket.io WebSocket endpoint. Running them on the same port keeps
 *   the deployment story simple (one container, one port).
 *
 * What this file does:
 *   1. Validates critical env vars up front and fails fast.
 *   2. Boots Next.js.
 *   3. Attaches Socket.io (best-effort — the app still works without it).
 *   4. Handles SIGTERM / SIGINT so container restarts drain cleanly.
 */

const { createServer } = require('http')
const { parse } = require('url')
const next = require('next')

// ---------------------------------------------------------------------------
// 1. Env validation
// ---------------------------------------------------------------------------
// In production we refuse to boot without the Supabase URL + keys. The app
// has hard runtime dependencies on them and failing fast is much easier to
// debug than a request-time crash 30 seconds later.
//
// Optional vars (OPENAI_API_KEY, PAGERDUTY_*, GRAFANA_*) are not checked —
// the app degrades gracefully when they're missing.
const isProd = process.env.NODE_ENV === 'production'
const requiredInProd = [
  'NEXT_PUBLIC_SUPABASE_URL',
  'NEXT_PUBLIC_SUPABASE_ANON_KEY',
  'SUPABASE_SERVICE_ROLE_KEY',
  'NEXT_PUBLIC_APP_URL',
]

if (isProd) {
  const missing = requiredInProd.filter((k) => !process.env[k])
  if (missing.length) {
    // eslint-disable-next-line no-console
    console.error(
      `[antops] Refusing to start: missing required env var(s): ${missing.join(', ')}.\n` +
      `See .env.example (hosted Supabase) or .env.selfhosted.example (Docker).`,
    )
    process.exit(1)
  }
}

// ---------------------------------------------------------------------------
// 2. Boot Next.js
// ---------------------------------------------------------------------------
const dev = !isProd
const hostname = process.env.HOSTNAME || '0.0.0.0'
const port = Number.parseInt(process.env.PORT || '3000', 10)

const app = next({ dev, hostname, port })
const handle = app.getRequestHandler()

app.prepare().then(() => {
  const server = createServer(async (req, res) => {
    try {
      const parsedUrl = parse(req.url, true)
      await handle(req, res, parsedUrl)
    } catch (err) {
      // eslint-disable-next-line no-console
      console.error('[antops] request handler error', req.url, err)
      res.statusCode = 500
      res.end('internal server error')
    }
  })

  // -------------------------------------------------------------------------
  // 3. Optional: attach Socket.io
  // -------------------------------------------------------------------------
  // The WebSocket server lives in TypeScript and is loaded dynamically so it
  // plays nicely with both the Next.js dev toolchain and the standalone
  // production bundle. Failure here is non-fatal — the rest of the app
  // continues to work without real-time features.
  let io = null
  import('./src/lib/websocket-server.ts')
    .then(({ wsServer }) => {
      io = wsServer.init(server)
      // NOTE: exposing these on `global` is a known anti-pattern and is
      // scheduled to move to a proper module export + Redis adapter. See
      // ANTOPS_AUDIT.md §3.5. Kept for now so API routes that broadcast via
      // `global.io` keep working.
      global.io = io
      global.userSessions = wsServer.userSessions || new Map()
      // eslint-disable-next-line no-console
      console.log('[antops] websocket server ready')
    })
    .catch((err) => {
      // eslint-disable-next-line no-console
      console.warn('[antops] websocket server failed to init, continuing without real-time:', err.message)
    })

  // -------------------------------------------------------------------------
  // 4. Graceful shutdown
  // -------------------------------------------------------------------------
  // Docker sends SIGTERM on `docker stop`. Without a handler, Node kills
  // open sockets abruptly — users see "connection reset" errors. Here we
  // stop accepting new connections, drain existing ones, and only then exit.
  const SHUTDOWN_TIMEOUT_MS = 10_000
  let shuttingDown = false
  function shutdown(signal) {
    if (shuttingDown) return
    shuttingDown = true
    // eslint-disable-next-line no-console
    console.log(`[antops] ${signal} received — draining connections`)
    const forceExit = setTimeout(() => {
      // eslint-disable-next-line no-console
      console.warn('[antops] shutdown took too long, forcing exit')
      process.exit(1)
    }, SHUTDOWN_TIMEOUT_MS)
    forceExit.unref()

    Promise.resolve()
      .then(() => io && new Promise((r) => io.close(r)))
      .then(() => new Promise((r) => server.close(r)))
      .then(() => {
        // eslint-disable-next-line no-console
        console.log('[antops] clean shutdown complete')
        process.exit(0)
      })
      .catch((err) => {
        // eslint-disable-next-line no-console
        console.error('[antops] shutdown error', err)
        process.exit(1)
      })
  }
  process.on('SIGTERM', () => shutdown('SIGTERM'))
  process.on('SIGINT', () => shutdown('SIGINT'))

  server.listen(port, hostname, (err) => {
    if (err) throw err
    // eslint-disable-next-line no-console
    console.log(`[antops] ready on http://${hostname}:${port} (${isProd ? 'production' : 'development'})`)
  })
})
