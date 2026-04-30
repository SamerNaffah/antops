import { NextRequest } from 'next/server'
import { createSupabaseServerClient } from './supabase'
import { validateApiToken } from './api-tokens'
import { UserRole } from './types'

export interface User {
  id: string
  email: string
  name: string
  fullName?: string
  organizationId: string
  role: UserRole
  // API token specific fields
  isApiTokenAuth?: boolean
  tokenId?: string
  tokenPermissions?: string[]
  tokenScope?: string
}

export interface AuthContext {
  user: User | null
  isAuthenticated: boolean
  authMethod: 'session' | 'api_token' | null
}

/**
 * Enhanced authentication that supports both session cookies and API tokens
 */
export async function getAuthenticatedUser(request?: NextRequest): Promise<AuthContext> {
  // Try API token first if Authorization header is present
  if (request) {
    const authHeader = request.headers.get('authorization')
    if (authHeader) {
      const apiUser = await authenticateWithApiToken(authHeader, request)
      if (apiUser) {
        return {
          user: apiUser,
          isAuthenticated: true,
          authMethod: 'api_token'
        }
      }
    }
  }
  
  // Fall back to session-based authentication
  const sessionUser = await authenticateWithSession()
  if (sessionUser) {
    return {
      user: sessionUser,
      isAuthenticated: true,
      authMethod: 'session'
    }
  }
  
  return {
    user: null,
    isAuthenticated: false,
    authMethod: null
  }
}

/**
 * Authenticate using session cookies (existing method)
 */
async function authenticateWithSession(): Promise<User | null> {
  const supabase = await createSupabaseServerClient()
  
  const { data: { user }, error } = await supabase.auth.getUser()
  
  if (error || !user) {
    return null
  }

  // Get profile data with organization info
  const { data: profile } = await supabase
    .from('profiles')
    .select('full_name, organization_id, role')
    .eq('id', user.id)
    .single()

  return {
    id: user.id,
    email: user.email!,
    name: profile?.full_name || user.user_metadata?.full_name || '',
    fullName: profile?.full_name || user.user_metadata?.full_name || '',
    organizationId: profile?.organization_id || '',
    role: profile?.role || 'member',
    isApiTokenAuth: false
  }
}

/**
 * Authenticate using API token from Authorization header
 */
async function authenticateWithApiToken(authHeader: string, request: NextRequest): Promise<User | null> {
  // Extract token from "Bearer <token>" format
  const tokenMatch = authHeader.match(/^Bearer\s+(.+)$/i)
  if (!tokenMatch) {
    return null
  }
  
  const token = tokenMatch[1]
  
  // Get client IP for logging
  const clientIp = request.headers.get('x-forwarded-for') || 
                   request.headers.get('x-real-ip') || 
                   'unknown'
  
  // Validate the token
  const tokenValidation = await validateApiToken(token, clientIp)
  
  if (!tokenValidation || !tokenValidation.isValid || !tokenValidation.userId) {
    return null
  }
  
  // Get user profile data - use admin client to bypass RLS
  const { supabaseAdmin } = await import('./supabase')
  
  const { data: _profiles, error: profileError } = await supabaseAdmin
    .from('profiles')
    .select('full_name, email, organization_id, role')
    .eq('id', tokenValidation.userId)
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const profile: any = (_profiles as any[])?.[0]
  
  if (!profile) {
    return null
  }
  
  return {
    id: tokenValidation.userId,
    email: profile.email,
    name: profile.full_name || '',
    fullName: profile.full_name || '',
    organizationId: tokenValidation.organizationId!,
    role: profile.role || 'member',
    isApiTokenAuth: true,
    tokenId: tokenValidation.tokenId,
    tokenPermissions: tokenValidation.permissions,
    tokenScope: tokenValidation.scope
  }
}

/**
 * Backward compatibility: Get user (session-based)
 */
export async function getUser(): Promise<User | null> {
  return authenticateWithSession()
}

/**
 * Check if user has required permissions for API token access
 */
export function hasApiPermission(user: User, requiredPermission: 'read' | 'write'): boolean {
  // Session users have full access
  if (!user.isApiTokenAuth) {
    return true
  }
  
  // API token users need specific permissions
  const permissions = user.tokenPermissions || []
  
  // 'write' permission implies 'read' permission
  if (requiredPermission === 'read') {
    return permissions.includes('read') || permissions.includes('write')
  }
  
  if (requiredPermission === 'write') {
    return permissions.includes('write')
  }
  
  return false
}

/**
 * Check if user has access to specific scope
 */
export function hasApiScope(user: User, requiredScope: string): boolean {
  // Session users have full access
  if (!user.isApiTokenAuth) {
    return true
  }
  
  const tokenScope = user.tokenScope || 'full'
  
  // Full scope allows everything
  if (tokenScope === 'full') {
    return true
  }
  
  // Exact scope match
  if (tokenScope === requiredScope) {
    return true
  }
  
  // Add more scope logic as needed
  // e.g., 'incidents_read' includes 'incidents'
  if (tokenScope.startsWith(requiredScope + '_')) {
    return true
  }
  
  return false
}

/**
 * Middleware helper to authenticate API requests
 */
export async function authenticateApiRequest(request: NextRequest): Promise<{
  success: boolean
  user?: User
  error?: string
  status?: number
}> {
  const auth = await getAuthenticatedUser(request)
  
  if (!auth.isAuthenticated || !auth.user) {
    return {
      success: false,
      error: 'Authentication required',
      status: 401
    }
  }
  
  return {
    success: true,
    user: auth.user
  }
}

/**
 * Check if API token has required permissions and scope
 */
export function validateApiAccess(
  user: User, 
  requiredPermission: 'read' | 'write' = 'read',
  requiredScope: string = 'full'
): { success: boolean; error?: string; status?: number } {
  
  // Check permissions
  if (!hasApiPermission(user, requiredPermission)) {
    return {
      success: false,
      error: `Insufficient permissions. Required: ${requiredPermission}`,
      status: 403
    }
  }
  
  // Check scope
  if (!hasApiScope(user, requiredScope)) {
    return {
      success: false,
      error: `Access denied. Required scope: ${requiredScope}`,
      status: 403
    }
  }
  
  return { success: true }
}