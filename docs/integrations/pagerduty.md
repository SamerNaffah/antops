# PagerDuty Integration Documentation

## Overview

The PagerDuty integration allows your system to receive alerts from PagerDuty and automatically create notifications that can be converted into incidents with pre-filled data.

## Features

- ✅ **Settings UI**: Configure PagerDuty integration in `/settings` → Integrations tab
- ✅ **Webhook Endpoint**: Receive PagerDuty webhooks at `/api/webhooks/pagerduty`
- ✅ **Notifications**: PagerDuty alerts appear in the notification bell
- ✅ **Auto-prefill**: Click notifications to create incidents with PagerDuty data
- ✅ **Field Mapping**: Maps PagerDuty fields to incident form fields
- ✅ **Database Schema**: Stores integration configuration securely

## Setup Instructions

### 1. Database Setup
Run the database migration:
```sql
-- Execute the SQL in: database-migrations/pagerduty_integration_table.sql
```

### 2. Configure Integration
1. Go to `/settings` → **Integrations** tab
2. Enable PagerDuty integration
3. Copy the webhook URL provided
4. Enter your PagerDuty API key
5. Optionally add integration key for filtering
6. Test the connection
7. Save configuration

### 3. Configure PagerDuty
1. In PagerDuty, go to **Services & Integrations**
2. Select the service you want to integrate
3. Add a new **Generic Webhook** integration
4. Paste the webhook URL from step 2
5. Configure to send the following events:
   - `incident.triggered`
   - `incident.acknowledged`
   - `incident.resolved`

## Webhook Payload Example

PagerDuty sends webhooks in this format:

```json
{
  "messages": [
    {
      "id": "webhook-event-id",
      "type": "incident.triggered",
      "created_on": "2025-01-15T12:00:00Z",
      "data": {
        "incident": {
          "id": "incident-123",
          "title": "Database Connection Issues",
          "description": "Connection timeouts on primary DB",
          "status": "triggered",
          "urgency": "high",
          "created_at": "2025-01-15T12:00:00Z",
          "html_url": "https://your-org.pagerduty.com/incidents/incident-123",
          "service": {
            "id": "service-456",
            "name": "Database Service"
          }
        }
      }
    }
  ]
}
```

## Field Mapping

| PagerDuty Field | Incident Field | Notes |
|----------------|----------------|-------|
| `incident.title` | `title` | Prefixed with "[PagerDuty]" |
| `incident.description` | `description` | Enhanced with PagerDuty metadata |
| `incident.urgency` | `criticality` & `urgency` | high → high, low → medium |
| `incident.status` | `status` | triggered → open, acknowledged → investigating |
| `incident.service.name` | `customer` | Service name as customer |
| Auto-generated | `tags` | Includes source:pagerduty, service:name, urgency:level, pagerduty-id:xxx |

## Notification Flow

1. **PagerDuty Alert** → Webhook sent to `/api/webhooks/pagerduty`
2. **Webhook Processing** → Creates notification for all users
3. **Notification Bell** → Shows alert with PagerDuty icon
4. **Click Notification** → Redirects to `/incidents/new` with prefilled data
5. **User Decision** → User can review, modify, and create incident

## API Endpoints

### Integration Configuration
- `GET /api/integrations/pagerduty` - Get current configuration
- `POST /api/integrations/pagerduty` - Save/update configuration

### Connection Testing  
- `POST /api/integrations/pagerduty/test` - Test API key validity

### Webhook Receiver
- `POST /api/webhooks/pagerduty` - Receive PagerDuty webhooks
- `GET /api/webhooks/pagerduty` - Webhook verification endpoint

## Security Features

- ✅ **API Key Encryption**: API keys are hidden in UI after saving
- ✅ **Organization Isolation**: Users only see their org's configuration
- ✅ **Row Level Security**: Database policies enforce access control
- ✅ **Webhook Validation**: Basic validation of PagerDuty payloads

## Testing the Integration

### Manual Test with curl:

```bash
# Test webhook endpoint
curl -X POST http://localhost:3000/api/webhooks/pagerduty \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{
      "id": "test-123",
      "type": "incident.triggered",
      "created_on": "2025-01-15T12:00:00Z",
      "data": {
        "incident": {
          "id": "test-incident-456",
          "title": "Test Database Alert",
          "description": "This is a test alert",
          "status": "triggered",
          "urgency": "high",
          "created_at": "2025-01-15T12:00:00Z",
          "html_url": "https://test.pagerduty.com/incidents/test-incident-456",
          "service": {
            "id": "test-service-789",
            "name": "Test Database Service"
          }
        }
      }
    }]
  }'
```

### Test Connection:
```bash
curl -X POST http://localhost:3000/api/integrations/pagerduty/test \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -d '{"apiKey": "YOUR_PAGERDUTY_API_KEY"}'
```

## Troubleshooting

### Common Issues:

1. **Webhook not receiving events**
   - Check PagerDuty webhook URL is correct
   - Verify webhook is enabled for the right events
   - Check server logs for errors

2. **API key test fails**
   - Verify API key has correct permissions
   - Check if key is expired
   - Ensure key is from correct PagerDuty account

3. **Notifications not appearing**
   - Check if integration is enabled
   - Verify users exist in database
   - Check notification polling interval (30s)

4. **Incident form not pre-filling**
   - Check browser console for errors
   - Verify URL parameters are being passed
   - Check if notification data includes prefill object

### Debug Mode:
Enable debug logging in the webhook handler by checking server logs for:
- `🔔 PagerDuty webhook received`
- `📦 PagerDuty payload: ...`
- `✅ Created PagerDuty notification for user ...`

## Future Enhancements

Possible improvements:
- [ ] Webhook signature validation
- [ ] Support for more PagerDuty event types
- [ ] Bi-directional sync (create PagerDuty incidents from our system)
- [ ] Custom field mapping configuration
- [ ] Integration with specific teams/users based on escalation policies
- [ ] PagerDuty incident updates when our incidents change status