import { createClient } from '@supabase/supabase-js'
import { createServerClient } from '@supabase/ssr'

// ---------------------------------------------------------------------------
// Why lazy getters?
//
// next build executes every route module during "Collecting page data". The
// Supabase constructor throws "supabaseUrl is required" when env vars are
// absent from the Docker build context (they are runtime-only variables).
// Never call createClient() at module load time — use the getters below.
// ---------------------------------------------------------------------------

let _supabase: ReturnType<typeof createClient> | null = null

export function getSupabaseClient(): ReturnType<typeof createClient> {
  if (!_supabase) {
    _supabase = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    )
  }
  return _supabase
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const makeProxy = (getter: () => ReturnType<typeof createClient>): ReturnType<typeof createClient> =>
  new Proxy({} as ReturnType<typeof createClient>, {
    get(_target, prop) {
      const client = getter()
      const val = (client as any)[prop]
      return typeof val === 'function' ? val.bind(client) : val
    },
  })

/** Lazy-init client-side Supabase client. Fully typed. */
export const supabase: ReturnType<typeof createClient> = makeProxy(getSupabaseClient)

// ---------------------------------------------------------------------------
// Server-side client (authenticated requests via cookies)
// ---------------------------------------------------------------------------
export async function createSupabaseServerClient() {
  const { cookies } = await import('next/headers')
  const cookieStore = await cookies()

  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get(name: string) {
          return cookieStore.get(name)?.value
        },
        set(name: string, value: string, options: any) {
          cookieStore.set({ name, value, ...options })
        },
        remove(name: string, options: any) {
          cookieStore.delete(name)
        },
      },
    }
  )
}

// ---------------------------------------------------------------------------
// Service role client (bypasses RLS) — lazy singleton
// ---------------------------------------------------------------------------
let _supabaseAdmin: ReturnType<typeof createClient> | null = null

export function getSupabaseAdmin(): ReturnType<typeof createClient> {
  if (!_supabaseAdmin) {
    _supabaseAdmin = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.SUPABASE_SERVICE_ROLE_KEY!,
      {
        auth: {
          autoRefreshToken: false,
          persistSession: false,
        },
      },
    )
  }
  return _supabaseAdmin
}

/** Lazy-init service-role Supabase client. Bypasses RLS. Fully typed. */
export const supabaseAdmin: ReturnType<typeof createClient> = makeProxy(getSupabaseAdmin)
