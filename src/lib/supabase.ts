import { createClient } from '@supabase/supabase-js'
import { createServerClient } from '@supabase/ssr'

// Client-side Supabase client — lazy singleton so the module can be imported
// at build time without NEXT_PUBLIC_SUPABASE_URL being present.
let _supabase: ReturnType<typeof createClient> | null = null
export function getSupabaseClient() {
  if (!_supabase) {
    _supabase = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    )
  }
  return _supabase
}
/** @deprecated Use getSupabaseClient() — avoids build-time init crash */
export const supabase = new Proxy({} as ReturnType<typeof createClient>, {
  get(_t, prop) {
    return (getSupabaseClient() as any)[prop]
  },
})

// Server-side Supabase client (for authenticated requests)
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

// Service role client for server-side operations (bypasses RLS) — lazy singleton
let _supabaseAdmin: ReturnType<typeof createClient> | null = null
export function getSupabaseAdmin() {
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
/** @deprecated Use getSupabaseAdmin() — avoids build-time init crash */
export const supabaseAdmin = new Proxy({} as ReturnType<typeof createClient>, {
  get(_t, prop) {
    return (getSupabaseAdmin() as any)[prop]
  },
})

