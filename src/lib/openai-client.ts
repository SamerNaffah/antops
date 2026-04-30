import OpenAI from 'openai'
import { createSupabaseServerClient } from './supabase'

// GPT-4o Mini pricing per token (as of 2024)
const PRICING = {
  'gpt-4o-mini': {
    input: 0.00015 / 1000,  // $0.15 per 1M input tokens
    output: 0.0006 / 1000   // $0.60 per 1M output tokens
  }
}

interface OpenAIConfig {
  model: string
  maxTokens?: number
  temperature?: number
  timeout?: number
  maxRetries?: number
}

interface TokenUsage {
  organizationId: string
  model: string
  inputTokens: number
  outputTokens: number
  totalTokens: number
  cost: number
  endpoint: string
  timestamp: string
}

class OpenAIClient {
  private client: OpenAI
  private config: OpenAIConfig

  constructor(config: Partial<OpenAIConfig> = {}) {
    this.config = {
      model: 'gpt-4o-mini',
      maxTokens: 1000,
      temperature: 0.7,
      timeout: 30000, // 30 seconds
      maxRetries: 3,
      ...config
    }

    if (!process.env.OPENAI_API_KEY) {
      // Defer the hard failure to first actual use so the module can be
      // imported at build time without OPENAI_API_KEY present.
      this.client = null as unknown as OpenAI
      return
    }

    this.client = new OpenAI({
      apiKey: process.env.OPENAI_API_KEY,
      timeout: this.config.timeout,
      maxRetries: this.config.maxRetries,
    })
  }

  /**
   * Generate a chat completion with GPT-4o Mini
   */
  async generateCompletion(
    messages: OpenAI.Chat.Completions.ChatCompletionMessageParam[],
    organizationId: string,
    endpoint: string = 'chat-completion',
    options: Partial<OpenAIConfig> = {}
  ): Promise<{
    content: string
    usage: OpenAI.Completions.CompletionUsage | undefined
    cost: number
  }> {
    const startTime = Date.now()
    if (!this.client) {
      throw new Error('OPENAI_API_KEY environment variable is required')
    }

    const requestConfig = { ...this.config, ...options }

    try {
      console.log(`[OpenAI] Starting ${requestConfig.model} request for org ${organizationId}`, {
        endpoint,
        model: requestConfig.model,
        messageCount: messages.length,
        maxTokens: requestConfig.maxTokens,
        temperature: requestConfig.temperature
      })

      const completion = await this.client.chat.completions.create({
        model: requestConfig.model,
        messages,
        max_tokens: requestConfig.maxTokens,
        temperature: requestConfig.temperature,
        stream: false,
      })

      const endTime = Date.now()
      const duration = endTime - startTime

      const content = completion.choices[0]?.message?.content || ''
      const usage = completion.usage
      const cost = this.calculateCost(usage, requestConfig.model)

      console.log(`[OpenAI] Request completed successfully`, {
        organizationId,
        endpoint,
        model: requestConfig.model,
        duration: `${duration}ms`,
        inputTokens: usage?.prompt_tokens || 0,
        outputTokens: usage?.completion_tokens || 0,
        totalTokens: usage?.total_tokens || 0,
        cost: `$${cost.toFixed(6)}`,
        contentLength: content.length
      })

      // Log token usage for cost monitoring
      if (usage) {
        await this.logTokenUsage({
          organizationId,
          model: requestConfig.model,
          inputTokens: usage.prompt_tokens,
          outputTokens: usage.completion_tokens,
          totalTokens: usage.total_tokens,
          cost,
          endpoint,
          timestamp: new Date().toISOString()
        })
      }

      return {
        content,
        usage,
        cost
      }

    } catch (error) {
      const endTime = Date.now()
      const duration = endTime - startTime

      console.error(`[OpenAI] Request failed`, {
        organizationId,
        endpoint,
        model: requestConfig.model,
        duration: `${duration}ms`,
        error: error instanceof Error ? error.message : 'Unknown error',
        errorType: error instanceof Error ? error.constructor.name : 'Unknown'
      })

      // Handle specific OpenAI errors
      if (error instanceof OpenAI.APIError) {
        throw new Error(`OpenAI API Error: ${error.message} (Status: ${error.status})`)
      } else if (error instanceof OpenAI.APIConnectionError) {
        throw new Error('OpenAI API Connection Error: Unable to connect to OpenAI services')
      } else if (error instanceof OpenAI.RateLimitError) {
        throw new Error('OpenAI Rate Limit Error: Too many requests, please try again later')
      } else if (error instanceof OpenAI.APIConnectionTimeoutError) {
        throw new Error('OpenAI API Timeout Error: Request timed out after 30 seconds')
      } else {
        throw new Error(`OpenAI Request Failed: ${error instanceof Error ? error.message : 'Unknown error'}`)
      }
    }
  }

  /**
   * Calculate cost based on token usage and model pricing
   */
  private calculateCost(
    usage: OpenAI.Completions.CompletionUsage | undefined,
    model: string
  ): number {
    if (!usage || !PRICING[model as keyof typeof PRICING]) {
      return 0
    }

    const pricing = PRICING[model as keyof typeof PRICING]
    const inputCost = usage.prompt_tokens * pricing.input
    const outputCost = usage.completion_tokens * pricing.output
    
    return inputCost + outputCost
  }

  /**
   * Log token usage to database for cost monitoring
   */
  private async logTokenUsage(usage: TokenUsage): Promise<void> {
    try {
      const supabase = await createSupabaseServerClient()
      
      const { error } = await supabase
        .from('openai_usage_logs')
        .insert({
          organization_id: usage.organizationId,
          model: usage.model,
          input_tokens: usage.inputTokens,
          output_tokens: usage.outputTokens,
          total_tokens: usage.totalTokens,
          cost: usage.cost,
          endpoint: usage.endpoint,
          created_at: usage.timestamp
        })

      if (error) {
        console.error('[OpenAI] Failed to log token usage:', error)
        // Don't throw error to avoid breaking the main request
      }
    } catch (error) {
      console.error('[OpenAI] Failed to log token usage:', error)
      // Don't throw error to avoid breaking the main request
    }
  }

  /**
   * Get cost summary for an organization
   */
  async getCostSummary(organizationId: string, days: number = 30): Promise<{
    totalCost: number
    totalTokens: number
    requestCount: number
    averageCostPerRequest: number
    costByModel: Record<string, number>
    costByEndpoint: Record<string, number>
  }> {
    try {
      const supabase = await createSupabaseServerClient()
      const startDate = new Date()
      startDate.setDate(startDate.getDate() - days)

      const { data, error } = await supabase
        .from('openai_usage_logs')
        .select('*')
        .eq('organization_id', organizationId)
        .gte('created_at', startDate.toISOString())

      if (error) {
        throw new Error(`Failed to fetch usage data: ${error.message}`)
      }

      const logs = data || []
      
      const totalCost = logs.reduce((sum, log) => sum + log.cost, 0)
      const totalTokens = logs.reduce((sum, log) => sum + log.total_tokens, 0)
      const requestCount = logs.length
      const averageCostPerRequest = requestCount > 0 ? totalCost / requestCount : 0

      const costByModel = logs.reduce((acc, log) => {
        acc[log.model] = (acc[log.model] || 0) + log.cost
        return acc
      }, {} as Record<string, number>)

      const costByEndpoint = logs.reduce((acc, log) => {
        acc[log.endpoint] = (acc[log.endpoint] || 0) + log.cost
        return acc
      }, {} as Record<string, number>)

      return {
        totalCost,
        totalTokens,
        requestCount,
        averageCostPerRequest,
        costByModel,
        costByEndpoint
      }
    } catch (error) {
      console.error('[OpenAI] Failed to get cost summary:', error)
      throw error
    }
  }

  /**
   * Health check to verify OpenAI connection
   */
  async healthCheck(): Promise<{ status: 'ok' | 'error', message: string, responseTime?: number }> {
    const startTime = Date.now()
    
    try {
      // Simple test with minimal tokens
      const completion = await this.client.chat.completions.create({
        model: 'gpt-4o-mini',
        messages: [{ role: 'user', content: 'Say "OK"' }],
        max_tokens: 5,
        temperature: 0
      })

      const endTime = Date.now()
      const responseTime = endTime - startTime

      if (completion.choices[0]?.message?.content) {
        return {
          status: 'ok',
          message: 'OpenAI connection successful',
          responseTime
        }
      } else {
        return {
          status: 'error',
          message: 'OpenAI responded but no content received'
        }
      }
    } catch (error) {
      const endTime = Date.now()
      const responseTime = endTime - startTime

      return {
        status: 'error',
        message: error instanceof Error ? error.message : 'Unknown error',
        responseTime
      }
    }
  }
}

// Export singleton instance
export const openaiClient = new OpenAIClient()

// Export class for custom configurations
export { OpenAIClient }

// Export types
export type { TokenUsage, OpenAIConfig }