import { NextRequest, NextResponse } from 'next/server'
import { getUser } from '@/lib/auth'
import { getAuthenticatedUser } from '@/lib/auth-enhanced'
import { AICache } from '@/lib/ai-cache'
import { createSupabaseServerClient } from '@/lib/supabase'
import { withAIRateLimit } from '@/lib/ai-rate-limiting'
import OpenAI from 'openai'

// Lazy singleton — defer construction to request time so next build can
// import this module without OPENAI_API_KEY being present in the build env.
let _openai: OpenAI | null = null
function getOpenAI() {
  if (!_openai) _openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY })
  return _openai
}
const openai = new Proxy({} as OpenAI, {
  get(_t, prop) {
    const client = getOpenAI()
    const val = (client as any)[prop]
    return typeof val === 'function' ? val.bind(client) : val
  },
})

interface ComponentInsightsRequest {
  componentId: string
  analysisDepth: 'basic' | 'detailed' | 'comprehensive'
  includeFailurePaths: boolean
  includeDependencyAnalysis: boolean
  consumeToken?: boolean // Optional flag to control token consumption
}

export async function POST(request: NextRequest) {
  console.log('🚀 AI Component Insights API called')
  
  try {
    // Enhanced authentication
    const authContext = await getAuthenticatedUser(request)
    if (!authContext.isAuthenticated || !authContext.user) {
      console.log('❌ No user found')
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    }
    const user = authContext.user
    
    const body: ComponentInsightsRequest = await request.json()
    const { componentId, analysisDepth, includeFailurePaths, includeDependencyAnalysis, consumeToken = true } = body

    console.log('📋 Request body:', body)

    // Only check rate limiting if we need to consume a token
    if (consumeToken) {
      console.log('🔒 Checking AI rate limits for user:', user.id)
      const rateLimitResult = await withAIRateLimit(user.id, 1)
      
      if (!rateLimitResult.allowed) {
        console.log('❌ Rate limit exceeded:', rateLimitResult.error)
        return NextResponse.json({
          error: rateLimitResult.error,
          tokensRemaining: rateLimitResult.tokensRemaining,
          tokensLimit: rateLimitResult.tokensLimit,
          resetTime: rateLimitResult.resetTime
        }, { status: 429 })
      }
      
      console.log('✅ Rate limit passed. Tokens remaining:', rateLimitResult.tokensRemaining)
    } else {
      console.log('⏭️ Skipping rate limit check (consumeToken=false)')
    }

    if (!componentId) {
      console.log('❌ No component ID provided')
      return NextResponse.json({ error: 'Component ID is required' }, { status: 400 })
    }

    // Create cache key based on analysis parameters
    const cacheParams = {
      componentId,
      analysisDepth,
      includeFailurePaths,
      includeDependencyAnalysis
    }

    // Check cache first
    const cached = await AICache.get(
      user.organizationId,
      'component_insights',
      cacheParams,
      { ttlHours: 1 } // Cache for 1 hour
    )

    if (cached) {
      return NextResponse.json({
        status: 'success',
        insights: cached.aiResponse,
        cached: true,
        metadata: {
          cacheAge: Date.now() - new Date(cached.createdAt).getTime(),
          cost: cached.cost || 0
        }
      })
    }

    // Generate AI insights based on component analysis
    const insights = await generateComponentInsights(
      componentId, 
      analysisDepth, 
      includeFailurePaths, 
      includeDependencyAnalysis,
      user
    )

    // Cache the results
    await AICache.set(
      user.organizationId,
      'component_insights',
      cacheParams,
      insights,
      {
        confidenceScore: 0.95,
        cost: 0.001
      }
    )

    return NextResponse.json({
      status: 'success',
      insights,
      cached: false,
      metadata: {
        generatedAt: new Date().toISOString(),
        cost: 0.001
      }
    })

  } catch (error) {
    console.error('Component insights error:', error)
    return NextResponse.json({
      status: 'error',
      message: error instanceof Error ? error.message : 'Failed to generate insights'
    }, { status: 500 })
  }
}

async function generateComponentInsights(
  componentId: string,
  analysisDepth: string,
  includeFailurePaths: boolean,
  includeDependencyAnalysis: boolean,
  user: any
) {
  try {
    // 1. Get component data and linked items
    const componentData = await getComponentData(componentId)
    const linkedItems = await getLinkedItems(componentId)
    const infrastructureTopology = await getInfrastructureTopology(user.organizationId)
    
    // 2. Prepare AI analysis prompt
    const analysisPrompt = buildAnalysisPrompt(
      componentData, 
      linkedItems, 
      infrastructureTopology, 
      analysisDepth,
      includeFailurePaths,
      includeDependencyAnalysis
    )
    
    // 3. Call GPT-4o-mini for analysis
    const aiAnalysis = await callOpenAI(analysisPrompt)
    
    // Debug logging
    console.log('Component data:', componentData)
    console.log('Component ID:', componentId)
    console.log('Component label:', componentData?.label)
    
    // 4. Structure the response
    const insights = {
      componentId,
      componentTitle: componentData?.label || componentId,
      riskScore: aiAnalysis.riskScore,
      confidenceLevel: aiAnalysis.confidenceLevel,
      riskCategory: aiAnalysis.riskCategory,
      recommendations: aiAnalysis.recommendations,
      predictedFailures: includeFailurePaths ? aiAnalysis.predictedFailures : [],
      dependencies: includeDependencyAnalysis ? aiAnalysis.dependencies : [],
      lastUpdated: new Date(),
      metadata: {
        analysisType: 'ai-powered',
        dataPoints: linkedItems.totalCount,
        analysisDepth,
        includeFailurePaths,
        includeDependencyAnalysis,
        aiModel: 'gpt-4o-mini'
      }
    }
    
    console.log('Final insights componentTitle:', insights.componentTitle)

    return insights
  } catch (error) {
    console.error('AI analysis error:', error)
    // Fallback to basic analysis if AI fails
    return await generateFallbackInsights(componentId, analysisDepth, includeFailurePaths, includeDependencyAnalysis)
  }
}

function generateRecommendations(componentId: string, riskCategory: string, depth: string): string[] {
  const baseRecommendations = [
    'Update security patches and dependencies',
    'Implement automated health checks',
    'Review access controls and permissions'
  ]

  const riskSpecificRecs: Record<string, string[]> = {
    critical: [
      'URGENT: Scale resources immediately to handle increased load',
      'Implement failover mechanisms',
      'Set up real-time monitoring alerts'
    ],
    high: [
      'Increase monitoring frequency',
      'Review backup and recovery procedures',
      'Consider load balancing implementation'
    ],
    medium: [
      'Schedule regular maintenance windows',
      'Optimize resource allocation',
      'Review performance metrics'
    ],
    low: [
      'Maintain current monitoring levels',
      'Consider minor performance optimizations'
    ]
  }

  const recommendations = [...baseRecommendations]
  
  if (riskSpecificRecs[riskCategory]) {
    recommendations.push(...riskSpecificRecs[riskCategory])
  }

  if (depth === 'comprehensive') {
    recommendations.push(
      'Conduct dependency analysis',
      'Review compliance requirements',
      'Plan capacity scaling strategy'
    )
  }

  return recommendations.slice(0, depth === 'basic' ? 3 : depth === 'detailed' ? 5 : 8)
}

function generateFailurePredictions(riskCategory: string) {
  const predictions = []
  
  if (riskCategory === 'critical' || riskCategory === 'high') {
    predictions.push({
      probability: riskCategory === 'critical' ? 0.75 : 0.45,
      impact: riskCategory === 'critical' ? 'critical' : 'high',
      description: 'Service degradation due to resource exhaustion',
      timeframe: '2-6 hours'
    })
  }

  if (riskCategory !== 'low') {
    predictions.push({
      probability: 0.3,
      impact: 'medium',
      description: 'Potential connectivity issues during peak hours',
      timeframe: '1-3 days'
    })
  }

  predictions.push({
    probability: 0.15,
    impact: 'low',
    description: 'Minor performance degradation',
    timeframe: '1-2 weeks'
  })

  return predictions
}

function generateDependencies(componentId: string) {
  // Mock dependency analysis
  const dependencies = []
  const dependencyCount = Math.floor(Math.random() * 5) + 1

  for (let i = 0; i < dependencyCount; i++) {
    dependencies.push({
      componentId: `component-${i + 1}`,
      impactScore: Math.floor(Math.random() * 100),
      relationship: ['upstream', 'downstream', 'peer', 'shared-resource'][Math.floor(Math.random() * 4)]
    })
  }

  return dependencies
}

// Real data fetching functions
async function getComponentData(componentId: string) {
  const supabase = await createSupabaseServerClient()
  
  console.log('🔍 Querying database for componentId:', componentId)
  
  // Get component from infrastructure nodes
  const { data: infraData, error } = await supabase
    .from('infrastructure_nodes')
    .select('id, label, type')
    .eq('id', componentId)
    .single()
  
  console.log('📊 Database query result:', { data: infraData, error })
  
  return infraData
}

async function getLinkedItems(componentId: string) {
  const supabase = await createSupabaseServerClient()
  
  // Get linked incidents
  const { data: incidents } = await supabase
    .from('incidents')
    .select('id, title, status, priority, created_at, description')
    .contains('affected_services', [componentId])
  
  // Get linked problems
  const { data: problems } = await supabase
    .from('problems')
    .select('id, title, status, priority, created_at, description')
    .contains('affected_services', [componentId])
  
  // Get linked changes
  const { data: changes } = await supabase
    .from('changes')
    .select('id, title, status, priority, created_at, description')
    .contains('affected_services', [componentId])
  
  return {
    incidents: incidents || [],
    problems: problems || [],
    changes: changes || [],
    totalCount: (incidents?.length || 0) + (problems?.length || 0) + (changes?.length || 0)
  }
}

async function getInfrastructureTopology(organizationId: string) {
  const supabase = await createSupabaseServerClient()
  
  // Get all infrastructure nodes and edges for topology analysis
  const { data: nodes } = await supabase
    .from('infrastructure_nodes')
    .select('*')
    .eq('organization_id', organizationId)
  
  const { data: edges } = await supabase
    .from('infrastructure_edges')
    .select('*')
    .eq('organization_id', organizationId)
  
  return { nodes: nodes || [], edges: edges || [] }
}

function buildAnalysisPrompt(componentData: any, linkedItems: any, topology: any, analysisDepth: string, includeFailurePaths: boolean, includeDependencyAnalysis: boolean) {
  return `You are an expert infrastructure analyst. Analyze this component and provide risk assessment.

COMPONENT DATA:
- ID: ${componentData?.id}
- Type: ${componentData?.data?.type}
- Name: ${componentData?.data?.label || componentData?.data?.customTitle}

LINKED ITIL ITEMS:
- Incidents: ${linkedItems.incidents.length}
${linkedItems.incidents.map((i: any) => `  * ${i.title} (${i.status}, ${i.priority})`).join('\n')}

- Problems: ${linkedItems.problems.length}
${linkedItems.problems.map((p: any) => `  * ${p.title} (${p.status}, ${p.priority})`).join('\n')}

- Changes: ${linkedItems.changes.length}
${linkedItems.changes.map((c: any) => `  * ${c.title} (${c.status}, ${c.priority})`).join('\n')}

TOPOLOGY CONNECTIONS:
- Total components in infrastructure: ${topology.nodes.length}
- Total connections: ${topology.edges.length}
- Connected to this component: ${topology.edges.filter((e: any) => e.source === componentData?.id || e.target === componentData?.id).length}

ANALYSIS REQUIREMENTS:
- Analysis Depth: ${analysisDepth}
- Include Failure Paths: ${includeFailurePaths}
- Include Dependencies: ${includeDependencyAnalysis}

Provide your analysis in this exact JSON format:
{
  "riskScore": <number 0-100>,
  "confidenceLevel": <number 0.0-1.0>,
  "riskCategory": "<low|medium|high|critical>",
  "recommendations": ["recommendation1", "recommendation2", "recommendation3"],
  "predictedFailures": [
    {
      "probability": <number 0.0-1.0>,
      "impact": "<low|medium|high|critical>",
      "description": "failure description",
      "timeframe": "timeframe estimate"
    }
  ],
  "dependencies": [
    {
      "componentId": "component-id",
      "impactScore": <number 0-100>,
      "relationship": "<upstream|downstream|peer|shared-resource>"
    }
  ]
}

Focus on:
1. How the incident/problem/change history indicates risk patterns
2. How network topology affects cascading failure risk
3. Specific recommendations based on component type and connections
4. Realistic failure predictions based on historical data

IMPORTANT: Base failure predictions ONLY on actual data provided above:
- Only predict failures if there are patterns in the incidents/problems/changes history
- Consider how component relationships could create cascading effects based on actual topology
- If there is insufficient historical data or no concerning patterns, return an empty predictedFailures array
- Do not make generic assumptions about component types - only use the actual ITIL data and relationships provided`
}

async function callOpenAI(prompt: string) {
  const response = await openai.chat.completions.create({
    model: 'gpt-4o-mini',
    messages: [
      {
        role: 'system',
        content: 'You are an expert infrastructure risk analyst. Always respond with valid JSON only, no additional text.'
      },
      {
        role: 'user',
        content: prompt
      }
    ],
    temperature: 0.3,
    max_tokens: 1500
  })
  
  const content = response.choices[0]?.message?.content
  if (!content) {
    throw new Error('No response from OpenAI')
  }
  
  try {
    return JSON.parse(content)
  } catch (error) {
    console.error('Failed to parse AI response:', content)
    throw new Error('Invalid AI response format')
  }
}

async function generateFallbackInsights(componentId: string, analysisDepth: string, includeFailurePaths: boolean, includeDependencyAnalysis: boolean) {
  // Simple fallback when AI fails
  let componentTitle = componentId
  
  // Try to get component title even in fallback
  try {
    const componentData = await getComponentData(componentId)
    componentTitle = componentData?.label || componentId
  } catch (error) {
    // If we can't get component data, use componentId as title
    componentTitle = componentId
  }
  
  return {
    componentId,
    componentTitle,
    riskScore: 30,
    confidenceLevel: 0.6,
    riskCategory: 'medium' as const,
    recommendations: [
      'Unable to perform AI analysis - check system connectivity',
      'Review component manually for potential issues',
      'Consider updating component monitoring'
    ],
    predictedFailures: includeFailurePaths ? [{
      probability: 0.2,
      impact: 'medium' as const,
      description: 'Potential service disruption (AI analysis unavailable)',
      timeframe: '1-7 days'
    }] : [],
    dependencies: includeDependencyAnalysis ? [] : [],
    lastUpdated: new Date(),
    metadata: {
      analysisType: 'fallback',
      dataPoints: 0,
      analysisDepth,
      includeFailurePaths,
      includeDependencyAnalysis,
      aiModel: 'fallback'
    }
  }
}