import crypto from 'crypto'
import { createSupabaseServerClient } from './supabase'

export interface ApiToken {
  id: string
  userId: string
  organizationId: string
  name: string
  tokenPrefix: string
  permissions: string[]
  scope: string
  lastUsedAt?: string
  lastUsedIp?: string
  usageCount: number
  expiresAt?: string
  isActive: boolean
  createdAt: string
}

export interface CreateTokenRequest {
  name: string
  expiresAt?: string // ISO string, optional
  permissions?: string[]
  scope?: string
}

export interface GeneratedToken {
  token: string // Full token (only returned once)
  tokenData: ApiToken
}

/**
 * Generate a secure API token with the format:
 * antops_sk_live_[32_random_chars]
 */
export function generateApiToken(environment: 'live' | 'test' = 'live'): { token: string; hash: string; prefix: string } {
  // Generate 32 random bytes and convert to hex (64 chars)
  const randomBytes = crypto.randomBytes(32).toString('hex')
  
  // Create the full token
  const token = `antops_sk_${environment}_${randomBytes}`
  
  // Hash the token for storage (never store plain text)
  const hash = crypto.createHash('sha256').update(token).digest('hex')
  
  // Create prefix for display (first 12 chars)
  const prefix = token.substring(0, 12) + '...'
  
  return { token, hash, prefix }
}

/**
 * Hash a token for comparison
 */
export function hashToken(token: string): string {
  return crypto.createHash('sha256').update(token).digest('hex')
}

/**
 * Validate token format
 */
export function isValidTokenFormat(token: string): boolean {
  // antops_sk_live_[64 hex chars] or antops_sk_test_[64 hex chars]
  const tokenRegex = /^antops_sk_(live|test)_[a-f0-9]{64}$/
  return tokenRegex.test(token)
}

/**
 * Create a new API token for a user
 */
export async function createApiToken(
  userId: string, 
  organizationId: string, 
  request: CreateTokenRequest
): Promise<GeneratedToken> {
  const supabase = await createSupabaseServerClient()
  
  // Validate inputs
  if (!request.name || request.name.trim().length === 0) {
    throw new Error('Token name is required')
  }
  
  if (request.name.length > 100) {
    throw new Error('Token name must be less than 100 characters')
  }
  
  // Check if user already has a token with this name
  const { data: existingToken } = await supabase
    .from('api_tokens')
    .select('id')
    .eq('user_id', userId)
    .eq('name', request.name.trim())
    .eq('is_active', true)
    .single()
  
  if (existingToken) {
    throw new Error('You already have an active token with this name')
  }
  
  // Generate token
  const environment = process.env.NODE_ENV === 'production' ? 'live' : 'test'
  const { token, hash, prefix } = generateApiToken(environment as 'live' | 'test')
  
  // Validate expiration date
  let expiresAt: string | null = null
  if (request.expiresAt) {
    const expDate = new Date(request.expiresAt)
    if (expDate <= new Date()) {
      throw new Error('Expiration date must be in the future')
    }
    if (expDate > new Date(Date.now() + 365 * 24 * 60 * 60 * 1000)) {
      throw new Error('Expiration date cannot be more than 1 year from now')
    }
    expiresAt = expDate.toISOString()
  }
  
  // Insert token into database
  const { data: tokenData, error } = await supabase
    .from('api_tokens')
    .insert({
      user_id: userId,
      organization_id: organizationId,
      name: request.name.trim(),
      token_hash: hash,
      token_prefix: prefix,
      permissions: request.permissions || ['read', 'write'],
      scope: request.scope || 'full',
      expires_at: expiresAt
    })
    .select()
    .single()
  
  if (error) {
    console.error('Error creating API token:', error)
    throw new Error('Failed to create API token')
  }
  
  return {
    token, // Full token (only returned once!)
    tokenData: {
      id: tokenData.id,
      userId: tokenData.user_id,
      organizationId: tokenData.organization_id,
      name: tokenData.name,
      tokenPrefix: tokenData.token_prefix,
      permissions: tokenData.permissions,
      scope: tokenData.scope,
      lastUsedAt: tokenData.last_used_at,
      lastUsedIp: tokenData.last_used_ip,
      usageCount: tokenData.usage_count,
      expiresAt: tokenData.expires_at,
      isActive: tokenData.is_active,
      createdAt: tokenData.created_at
    }
  }
}

/**
 * Validate an API token and return user info
 */
export async function validateApiToken(token: string, clientIp?: string): Promise<{
  isValid: boolean
  userId?: string
  organizationId?: string
  permissions?: string[]
  scope?: string
  tokenId?: string
} | null> {
  if (!token || !isValidTokenFormat(token)) {
    return { isValid: false }
  }
  
  // Use admin client for token validation to bypass RLS
  const { supabaseAdmin } = await import('./supabase')
  const supabase = supabaseAdmin
  const tokenHash = hashToken(token)
  
  // Find active token
  const { data: _tokensData, error } = await supabase
    .from('api_tokens')
    .select('*')
    .eq('token_hash', tokenHash)
    .eq('is_active', true)
  const tokensData = _tokensData as any[] | null

  if (error || !tokensData || tokensData.length === 0) {
    return { isValid: false }
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const tokenData: any = tokensData[0]
  
  // Check if token is expired
  if (tokenData.expires_at && new Date(tokenData.expires_at) <= new Date()) {
    // Mark token as inactive
    await supabase
      .from('api_tokens')
      .update({ is_active: false })
      .eq('id', tokenData.id)
    
    return { isValid: false }
  }
  
  // Update last used info (fire and forget - don't wait)
  supabase
    .from('api_tokens')
    .update({ 
      last_used_at: new Date().toISOString(),
      last_used_ip: clientIp,
      usage_count: tokenData.usage_count + 1
    })
    .eq('id', tokenData.id)
    .then(() => {}) // Silent update
  
  return {
    isValid: true,
    userId: tokenData.user_id,
    organizationId: tokenData.organization_id,
    permissions: tokenData.permissions,
    scope: tokenData.scope,
    tokenId: tokenData.id
  }
}

/**
 * Get all API tokens for a user
 */
export async function getUserApiTokens(userId: string): Promise<ApiToken[]> {
  const supabase = await createSupabaseServerClient()
  
  const { data: tokens, error } = await supabase
    .from('api_tokens')
    .select('*')
    .eq('user_id', userId)
    .eq('is_active', true)
    .order('created_at', { ascending: false })
  
  if (error) {
    console.error('Error fetching API tokens:', error)
    throw new Error('Failed to fetch API tokens')
  }
  
  return (tokens || []).map(token => ({
    id: token.id,
    userId: token.user_id,
    organizationId: token.organization_id,
    name: token.name,
    tokenPrefix: token.token_prefix,
    permissions: token.permissions,
    scope: token.scope,
    lastUsedAt: token.last_used_at,
    lastUsedIp: token.last_used_ip,
    usageCount: token.usage_count,
    expiresAt: token.expires_at,
    isActive: token.is_active,
    createdAt: token.created_at
  }))
}

/**
 * Revoke (deactivate) an API token
 */
export async function revokeApiToken(tokenId: string, userId: string): Promise<boolean> {
  const supabase = await createSupabaseServerClient()
  
  const { error } = await supabase
    .from('api_tokens')
    .update({ is_active: false })
    .eq('id', tokenId)
    .eq('user_id', userId) // Ensure user can only revoke their own tokens
  
  if (error) {
    console.error('Error revoking API token:', error)
    return false
  }
  
  return true
}

/**
 * Delete an API token permanently
 */
export async function deleteApiToken(tokenId: string, userId: string): Promise<boolean> {
  const supabase = await createSupabaseServerClient()
  
  const { error } = await supabase
    .from('api_tokens')
    .delete()
    .eq('id', tokenId)
    .eq('user_id', userId) // Ensure user can only delete their own tokens
  
  if (error) {
    console.error('Error deleting API token:', error)
    return false
  }
  
  return true
}

/**
 * Update an API token (name, expiration, etc.)
 */
export async function updateApiToken(
  tokenId: string, 
  userId: string, 
  updates: Partial<Pick<CreateTokenRequest, 'name' | 'expiresAt'>>
): Promise<boolean> {
  const supabase = await createSupabaseServerClient()
  
  const updateData: any = {}
  
  if (updates.name !== undefined) {
    if (!updates.name || updates.name.trim().length === 0) {
      throw new Error('Token name cannot be empty')
    }
    if (updates.name.length > 100) {
      throw new Error('Token name must be less than 100 characters')
    }
    updateData.name = updates.name.trim()
  }
  
  if (updates.expiresAt !== undefined) {
    if (updates.expiresAt) {
      const expDate = new Date(updates.expiresAt)
      if (expDate <= new Date()) {
        throw new Error('Expiration date must be in the future')
      }
      updateData.expires_at = expDate.toISOString()
    } else {
      updateData.expires_at = null // Remove expiration
    }
  }
  
  const { error } = await supabase
    .from('api_tokens')
    .update(updateData)
    .eq('id', tokenId)
    .eq('user_id', userId)
  
  if (error) {
    console.error('Error updating API token:', error)
    return false
  }
  
  return true
}