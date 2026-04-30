import { supabaseAdmin } from './supabase'

export interface AITokenStatus {
  tokensUsed: number
  tokensRemaining: number
  tokensLimit: number
  resetTime: Date
  canScan: boolean
}

export interface TokenConsumptionResult {
  success: boolean
  tokensRemaining: number
  tokensLimit: number
  message: string
}

/**
 * Check if a user has available AI scan tokens
 */
export async function checkAITokens(userId: string, requiredTokens: number = 1): Promise<{
  hasTokens: boolean
  tokensRemaining: number
  tokensLimit: number
  resetTime: Date
} | null> {
  try {
    const { data: _data, error } = await supabaseAdmin.rpc('check_ai_scan_tokens', {
      user_uuid: userId,
      required_tokens: requiredTokens
    })
    const data = _data as any[] | null

    if (error) {
      console.error('Error checking AI tokens:', error)
      return null
    }

    if (data && data.length > 0) {
      const result = data[0]
      return {
        hasTokens: result.has_tokens,
        tokensRemaining: result.tokens_remaining,
        tokensLimit: result.tokens_limit,
        resetTime: new Date(result.reset_time)
      }
    }

    return null
  } catch (error) {
    console.error('Failed to check AI tokens:', error)
    return null
  }
}

/**
 * Consume AI scan tokens for a user
 */
export async function consumeAITokens(userId: string, tokensToConsume: number = 1): Promise<TokenConsumptionResult | null> {
  try {
    const { data: _data, error } = await supabaseAdmin.rpc('consume_ai_scan_tokens', {
      user_uuid: userId,
      tokens_to_consume: tokensToConsume
    })
    const data = _data as any[] | null

    if (error) {
      console.error('Error consuming AI tokens:', error)
      return null
    }

    if (data && data.length > 0) {
      const result = data[0]
      return {
        success: result.success,
        tokensRemaining: result.tokens_remaining,
        tokensLimit: result.tokens_limit,
        message: result.message
      }
    }

    return null
  } catch (error) {
    console.error('Failed to consume AI tokens:', error)
    return null
  }
}

/**
 * Get user's current AI token status
 */
export async function getUserAITokenStatus(userId: string): Promise<AITokenStatus | null> {
  try {
    const { data: _data, error } = await supabaseAdmin.rpc('get_user_ai_scan_status', {
      user_uuid: userId
    })
    const data = _data as any[] | null

    if (error) {
      console.error('Error getting AI token status:', error)
      return null
    }

    if (data && data.length > 0) {
      const result = data[0]
      return {
        tokensUsed: result.tokens_used,
        tokensRemaining: result.tokens_remaining,
        tokensLimit: result.tokens_limit,
        resetTime: new Date(result.reset_time),
        canScan: result.can_scan
      }
    }

    return null
  } catch (error) {
    console.error('Failed to get AI token status:', error)
    return null
  }
}

/**
 * Calculate time until token reset (midnight next day)
 */
export function formatTimeUntilReset(resetTime: Date): string {
  const now = new Date()
  const diffMs = resetTime.getTime() - now.getTime()
  
  if (diffMs <= 0) {
    return 'Resetting now...'
  }
  
  const hours = Math.floor(diffMs / (1000 * 60 * 60))
  const minutes = Math.floor((diffMs % (1000 * 60 * 60)) / (1000 * 60))
  
  if (hours > 0) {
    return `${hours}h ${minutes}m`
  } else {
    return `${minutes}m`
  }
}

/**
 * Rate limiting middleware for API routes
 */
export async function withAIRateLimit(
  userId: string,
  requiredTokens: number = 1
): Promise<{
  allowed: boolean
  tokensRemaining?: number
  tokensLimit?: number
  resetTime?: Date
  error?: string
}> {
  const tokenCheck = await checkAITokens(userId, requiredTokens)
  
  if (!tokenCheck) {
    return {
      allowed: false,
      error: 'Failed to check AI token status'
    }
  }
  
  if (!tokenCheck.hasTokens) {
    return {
      allowed: false,
      tokensRemaining: tokenCheck.tokensRemaining,
      tokensLimit: tokenCheck.tokensLimit,
      resetTime: tokenCheck.resetTime,
      error: `Daily AI scan limit reached. You have ${tokenCheck.tokensRemaining} tokens remaining. Limit resets at midnight.`
    }
  }
  
  // Consume the tokens
  const consumption = await consumeAITokens(userId, requiredTokens)
  
  if (!consumption || !consumption.success) {
    return {
      allowed: false,
      error: consumption?.message || 'Failed to consume AI tokens'
    }
  }
  
  return {
    allowed: true,
    tokensRemaining: consumption.tokensRemaining,
    tokensLimit: consumption.tokensLimit
  }
}