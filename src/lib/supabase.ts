import { createClient } from '@supabase/supabase-js'
import { createServerClient } from '@supabase/ssr'

// ---------------------------------------------------------------------------
// Client-side Supabase client — lazy singleton.
//
// createClient() must NOT be called at module load time: next build executes
// all route modules during "Collecting page data" and the Supabase constructor
// throws "supabaseUrl is required" when env vars are absent from the build
// context (they're runtime-only). Call getSupabaseClient() instead.
// ---------------------------------------------------------------------------
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

// Convenience alias — same lazy singleton, fully typed.
export const supabase = {
  get from() { return getSupabaseClient().from.bind(getSupabaseClient()) },
  get auth() { return getSupabaseClient().auth },
  get storage() { return getSupabaseClient().storage },
  get functions() { return getSupabaseClient().functions },
  get rpc() { return getSupabaseClient().rpc.bind(getSupabaseClient()) },
  get realtime() { return getSupabaseClient().realtime },
  get channel() { return getSupabaseClient().channel.bind(getSupabaseClient()) },
  get removeChannel() { return getSupabaseClient().removeChannel.bind(getSupabaseClient()) },
  get removeAllChannels() { return getSupabaseClient().removeAllChannels.bind(getSupabaseClient()) },
  get getChannels() { return getSupabaseClient().getChannels.bind(getSupabaseClient()) },
} as unknown as ReturnType<typeof createClient>

// ---------------------------------------------------------------------------
// Server-side Supabase client (for authenticated requests)
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
// Service role client — lazy singleton, bypasses RLS.
// ---------------------------------------------------------------------------
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

// Convenience alias — same lazy singleton, fully typed.
export const supabaseAdmin = {
  get from() { return getSupabaseAdmin().from.bind(getSupabaseAdmin()) },
  get auth() { return getSupabaseAdmin().auth },
  get storage() { return getSupabaseAdmin().storage },
  get functions() { return getSupabaseAdmin().functions },
  get rpc() { return getSupabaseAdmin().rpc.bind(getSupabaseAdmin()) },
  get realtime() { return getSupabaseAdmin().realtime },
  get channel() { return getSupabaseAdmin().channel.bind(getSupabaseAdmin()) },
  get removeChannel() { return getSupabaseAdmin().removeChannel.bind(getSupabaseAdmin()) },
  get removeAllChannels() { return getSupabaseAdmin().removeAllChannels.bind(getSupabaseAdmin()) },
  get getChannels() { return getSupabaseAdmin().getChannels.bind(getSupabaseAdmin()) },
} as unknown as ReturnType<typeof createClient>
