# ANTOPS API Documentation

Welcome to the ANTOPS API! This RESTful API allows you to programmatically interact with your ITSM (IT Service Management) platform for managing incidents, problems, changes, and infrastructure components.


## Authentication

ANTOPS API supports two authentication methods:

### API Tokens
Generate API tokens through the Settings page in your ANTOPS dashboard. Include the token in the Authorization header:

```http
Authorization: Bearer antops_sk_live_[your_token_here]
```

## Rate Limiting

### AI Endpoints
AI-powered endpoints have a rate limiting per user per day:
- **5 AI scans per user per day**
- Resets daily at midnight
- Rate limit status available via `/api/ai/token-status`

### General API Endpoints
Standard rate limiting applies to prevent abuse. Contact support if you need higher limits.

## Response Format

All responses follow this structure:

```json
{
  "data": { ... },         // Success responses
  "error": "string",       // Error message (if applicable)
  "status": "success|error"
}
```

## Error Codes

- `200` - Success
- `201` - Created
- `400` - Bad Request
- `401` - Unauthorized
- `403` - Forbidden
- `404` - Not Found
- `429` - Rate Limited
- `500` - Internal Server Error

---

## Authentication Endpoints

### Get Current User
Get information about the authenticated user.

```http
GET /api/auth/me
```

**Response:**
```json
{
  "user": {
    "id": "user-uuid",
    "email": "user@example.com",
    "name": "John Doe",
    "organizationId": "org-uuid",
    "role": "owner",
    "isApiTokenAuth": true,
    "tokenPermissions": ["read", "write"],
    "tokenScope": "full"
  },
  "authMethod": "api_token"
}
```

### Manage API Tokens
Create, list, and manage your API tokens.

#### List API Tokens
```http
GET /api/auth/tokens
```

#### Create API Token
```http
POST /api/auth/tokens
Content-Type: application/json

{
  "name": "My Integration Token",
  "permissions": ["read", "write"],
  "scope": "full",
  "expiresAt": "2024-12-31T23:59:59Z"
}
```

**Response:**
```json
{
  "token": "antops_sk_live_[full_token_here]",
  "tokenData": {
    "id": "token-uuid",
    "name": "My Integration Token",
    "tokenPrefix": "antops_sk_li...",
    "permissions": ["read", "write"],
    "scope": "full",
    "expiresAt": "2024-12-31T23:59:59Z",
    "createdAt": "2024-01-15T10:30:00Z"
  }
}
```

#### Revoke API Token
```http
PUT /api/auth/tokens
Content-Type: application/json

{
  "action": "revoke",
  "tokenId": "token-uuid"
}
```

#### Delete API Token
```http
DELETE /api/auth/tokens?id=token-uuid
```

---

## Incident Management

### List Incidents
Retrieve all incidents for your organization.

```http
GET /api/incidents
```

**Response:**
```json
[
  {
    "id": "incident-uuid",
    "title": "Database Connection Issues",
    "description": "Users unable to connect to primary database",
    "status": "open",
    "priority": "high",
    "criticality": "major",
    "urgency": "high",
    "assignedTo": "user-uuid",
    "assignedToName": "John Doe",
    "affectedServices": ["web-app", "api"],
    "tags": ["database", "connectivity"],
    "createdAt": "2024-01-15T10:30:00Z",
    "updatedAt": "2024-01-15T11:45:00Z"
  }
]
```

### Create Incident
Create a new incident report.

```http
POST /api/incidents
Content-Type: application/json

{
  "title": "API Response Time Degradation",
  "description": "API endpoints showing increased response times",
  "priority": "medium",
  "criticality": "minor", 
  "urgency": "medium",
  "assignedTo": "user-uuid",
  "affectedServices": ["api", "web-app"],
  "tags": ["performance", "api"]
}
```

### Get Incident
Retrieve a specific incident by ID.

```http
GET /api/incidents/{incident-id}
```

### Update Incident
Update an existing incident.

```http
PUT /api/incidents/{incident-id}
Content-Type: application/json

{
  "status": "resolved",
  "description": "Updated description with resolution details"
}
```

---

## Problem Management

### List Problems
Retrieve all problems for your organization.

```http
GET /api/problems
```

**Response:**
```json
[
  {
    "id": "problem-uuid",
    "title": "Recurring Database Timeouts",
    "description": "Database connection timeouts occurring daily during peak hours",
    "status": "investigating",
    "priority": "high",
    "assignedTo": "user-uuid",
    "assignedToName": "Jane Smith",
    "relatedIncidents": ["incident-uuid-1", "incident-uuid-2"],
    "rootCause": "",
    "workaround": "Restart database connection pool every 2 hours",
    "createdAt": "2024-01-15T10:30:00Z",
    "updatedAt": "2024-01-15T11:45:00Z"
  }
]
```

### Create Problem
Create a new problem record.

```http
POST /api/problems
Content-Type: application/json

{
  "title": "Memory Leak in User Service",
  "description": "User service consuming excessive memory over time",
  "priority": "medium",
  "assignedTo": "user-uuid",
  "relatedIncidents": ["incident-uuid"]
}
```

### Get Problem
Retrieve a specific problem by ID.

```http
GET /api/problems/{problem-id}
```

### Update Problem
Update an existing problem.

```http
PUT /api/problems/{problem-id}
Content-Type: application/json

{
  "status": "resolved",
  "rootCause": "Memory leak in user session cache",
  "solution": "Implemented cache cleanup routine"
}
```

---

## Change Management

### List Changes
Retrieve all changes for your organization.

```http
GET /api/changes
```

**Response:**
```json
[
  {
    "id": "change-uuid",
    "title": "Database Schema Migration v2.1",
    "description": "Add new columns for user preferences",
    "status": "scheduled",
    "priority": "normal",
    "changeType": "standard",
    "assignedTo": "user-uuid",
    "assignedToName": "Bob Wilson",
    "scheduledStart": "2024-01-20T02:00:00Z",
    "scheduledEnd": "2024-01-20T04:00:00Z",
    "approvalStatus": "approved",
    "riskLevel": "low",
    "backoutPlan": "Restore from backup taken at 01:45",
    "createdAt": "2024-01-15T10:30:00Z",
    "updatedAt": "2024-01-15T11:45:00Z"
  }
]
```

### Create Change
Create a new change request.

```http
POST /api/changes
Content-Type: application/json

{
  "title": "Update SSL Certificates",
  "description": "Renew SSL certificates for all production domains",
  "priority": "high",
  "changeType": "standard",
  "assignedTo": "user-uuid",
  "scheduledStart": "2024-01-25T01:00:00Z",
  "scheduledEnd": "2024-01-25T02:00:00Z",
  "riskLevel": "medium",
  "backoutPlan": "Restore previous certificates from backup"
}
```

### Get Change
Retrieve a specific change by ID.

```http
GET /api/changes/{change-id}
```

### Update Change
Update an existing change.

```http
PUT /api/changes/{change-id}
Content-Type: application/json

{
  "status": "completed",
  "actualStart": "2024-01-25T01:00:00Z",
  "actualEnd": "2024-01-25T01:45:00Z"
}
```

### Change Approval
Approve or reject a change request.

```http
POST /api/changes/{change-id}/approval
Content-Type: application/json

{
  "action": "approve",
  "comments": "Change approved for scheduled maintenance window"
}
```

---

## Team Management

### List Team Members
Retrieve all team members in your organization.

```http
GET /api/team
```

**Response:**
```json
[
  {
    "id": "user-uuid",
    "name": "John Doe",
    "email": "john@example.com",
    "role": "admin",
    "jobTitle": "DevOps Engineer",
    "status": "active",
    "joinedAt": "2024-01-01T00:00:00Z"
  }
]
```

### Invite Team Member
Send an invitation to join your organization.

```http
POST /api/team/invite
Content-Type: application/json

{
  "email": "newuser@example.com",
  "role": "member",
  "name": "New User"
}
```

### Update Team Member Role
Update a team member's role.

```http
PUT /api/team/{member-id}/role
Content-Type: application/json

{
  "role": "admin"
}
```

---

## Organization Management

### Get Organization Stats
Retrieve organization metrics and statistics.

```http
GET /api/organization/stats
```

**Response:**
```json
{
  "totalMembers": 15,
  "openIncidents": 3,
  "activeProblems": 2,
  "activeChanges": 5,
  "slaComplianceRate": 95,
  "changeSuccessRate": 98,
  "criticalIncidents": 0,
  "highPriorityIncidents": 2,
  "incidentsResolvedToday": 7,
  "changesScheduledToday": 2,
  "averageResolutionTime": 4.5,
  "problemBacklog": 1,
  "emergencyChanges": 0,
  "slaBreaches": 0,
  "mttr": 3.2,
  "mtbf": 720.5
}
```

### Update Organization Settings
Update organization information.

```http
PUT /api/organization
Content-Type: application/json

{
  "name": "Updated Organization Name",
  "settings": {
    "timezone": "UTC",
    "notificationPreferences": {
      "email": true,
      "slack": false
    }
  }
}
```

---

## Infrastructure Management

### List Infrastructure Components
Retrieve infrastructure components.

```http
GET /api/infra
```

**Response:**
```json
{
  "nodes": [
    {
      "id": "component-uuid",
      "type": "server",
      "label": "Web Server 01",
      "metadata": {
        "type": "server",
        "customTitle": "Production Web Server",
        "linkedCount": 3
      },
      "position": { "x": 100, "y": 200 },
      "environmentId": "env-uuid"
    }
  ],
  "zones": [
    {
      "id": "zone-uuid",
      "name": "Production VPC",
      "type": "vpc",
      "components": ["component-uuid"]
    }
  ]
}
```

### Create Infrastructure Component
Add a new infrastructure component.

```http
POST /api/infra
Content-Type: application/json

{
  "nodes": [
    {
      "type": "server",
      "label": "Database Server 02",
      "metadata": {
        "type": "database",
        "customTitle": "Secondary Database"
      },
      "position": { "x": 300, "y": 400 }
    }
  ]
}
```

---

## AI-Powered Features

### Get AI Token Status
Check your AI scan token usage and limits.

```http
GET /api/ai/token-status
```

**Response:**
```json
{
  "tokensUsed": 2,
  "tokensRemaining": 3,
  "tokensLimit": 5,
  "canScan": true,
  "resetTime": "2024-01-16T00:00:00Z",
  "resetTimeFormatted": "13h 24m"
}
```

### AI Component Analysis
Analyze infrastructure components with AI insights.

```http
POST /api/ai/component-insights
Content-Type: application/json

{
  "componentId": "component-uuid",
  "analysisDepth": "basic",
  "includeFailurePaths": true,
  "includeDependencyAnalysis": true
}
```

**Response:**
```json
{
  "status": "success",
  "insights": {
    "riskScore": 75,
    "vulnerabilities": [
      {
        "type": "security",
        "severity": "medium",
        "description": "SSH access enabled on default port",
        "recommendation": "Change SSH port and implement key-based authentication"
      }
    ],
    "dependencies": [
      {
        "componentId": "database-uuid",
        "relationship": "depends_on",
        "criticality": "high"
      }
    ],
    "recommendations": [
      {
        "category": "performance",
        "priority": "medium",
        "description": "Consider implementing load balancing for high availability"
      }
    ]
  }
}
```

---

## Notification Management

### List Notifications
Retrieve user notifications.

```http
GET /api/notifications
```

**Response:**
```json
[
  {
    "id": "notification-uuid",
    "type": "incident_created",
    "title": "New Critical Incident",
    "message": "Critical incident #INC-001 has been created",
    "read": false,
    "createdAt": "2024-01-15T10:30:00Z",
    "relatedId": "incident-uuid"
  }
]
```

### Mark Notification as Read
Mark a specific notification as read.

```http
PUT /api/notifications/{notification-id}
Content-Type: application/json

{
  "read": true
}
```

### Mark All Notifications as Read
Mark all notifications as read.

```http
POST /api/notifications/mark-all-read
```

---

## Webhooks (Coming Soon)

ANTOPS will support webhooks for real-time event notifications:

- Incident created/updated/resolved
- Problem created/updated/resolved  
- Change approved/completed/failed
- SLA breaches
- AI analysis completed

---

## SDKs and Libraries

### Official SDKs
- **JavaScript/TypeScript**: `npm install @antops/sdk` (Coming Soon)
- **Python**: `pip install antops-sdk` (Coming Soon)
- **Go**: `go get github.com/antops/go-sdk` (Coming Soon)

### Community SDKs
Community-maintained SDKs will be listed here as they become available.

---

## Examples

### Complete Incident Workflow

```bash
# 1. Create an incident
curl -X POST "https://app.antopshq.com/api/incidents" \
  -H "Authorization: Bearer antops_sk_live_your_token_here" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Database Connection Issues",
    "description": "Primary database showing connection timeouts",
    "priority": "high",
    "criticality": "major",
    "urgency": "high",
    "affectedServices": ["web-app", "api"]
  }'

# 2. Update the incident
curl -X PUT "https://app.antopshq.com/api/incidents/{incident-id}" \
  -H "Authorization: Bearer antops_sk_live_your_token_here" \
  -H "Content-Type: application/json" \
  -d '{
    "status": "investigating",
    "description": "Updated: Found connection pool exhaustion"
  }'

# 3. Resolve the incident
curl -X PUT "https://app.antopshq.com/api/incidents/{incident-id}" \
  -H "Authorization: Bearer antops_sk_live_your_token_here" \
  -H "Content-Type: application/json" \
  -d '{
    "status": "resolved",
    "description": "Resolved: Increased connection pool size and added monitoring"
  }'
```

### AI-Powered Infrastructure Analysis

```bash
# 1. Check AI token status
curl "https://app.antopshq.com/api/ai/token-status" \
  -H "Authorization: Bearer antops_sk_live_your_token_here"

# 2. Analyze infrastructure component
curl -X POST "https://app.antopshq.com/api/ai/component-insights" \
  -H "Authorization: Bearer antops_sk_live_your_token_here" \
  -H "Content-Type: application/json" \
  -d '{
    "componentId": "server-uuid",
    "analysisDepth": "comprehensive",
    "includeFailurePaths": true,
    "includeDependencyAnalysis": true
  }'
```

---

## Support

### Getting Help
- **Email**: support@antopshq.com

---


---

*We make our best to update this list frequently. Last updated: 27th of August, 2025*