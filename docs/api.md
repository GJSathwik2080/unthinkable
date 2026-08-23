# API Documentation

All JSON responses use either `{ "success": true, "data": ... }` or `{ "success": false, "error": { "code", "message", "fieldErrors?" } }`.

## Public and customer APIs

| Method | Path | Access | Purpose |
|---|---|---|---|
| POST | `/api/auth/register` | Public | Create a customer account only |
| POST | `/api/auth/login` | Public | Create a secure Supabase session |
| POST | `/api/auth/guest` | Public unless disabled | Start a session for the fixed bootstrapped guest account for the requested role |
| POST | `/api/auth/logout` | Authenticated | End the current session |
| GET | `/api/auth/me` | Authenticated | Return the current profile and role |
| GET | `/api/dashboard` | Authenticated | Return metrics and recent orders scoped to the current role |
| GET | `/api/areas/lookup?postalCode=600001` | Public | Resolve postal code and zone |
| POST | `/api/orders/quote` | Public | Calculate an itemized delivery quote |
| POST | `/api/orders` | Customer/Admin | Recalculate and create an order |
| GET | `/api/orders` | Customer/Admin | List orders permitted to the caller |
| GET | `/api/orders/:id` | Owner/Admin/Agent | Get one order |
| GET | `/api/orders/:id/tracking` | Owner/Admin/Agent | Get immutable timeline |
| POST | `/api/orders/:id/reschedule` | Owner/Admin | Create a future attempt after failure |

### Quote request

```json
{
  "pickupPostalCode": "600001",
  "dropPostalCode": "600041",
  "lengthCm": 40,
  "breadthCm": 30,
  "heightCm": 20,
  "actualWeightKg": 3,
  "orderType": "B2C",
  "paymentType": "COD"
}
```

The response includes zones, movement type, actual/volumetric/billable weights, base charge, additional-weight charge, COD charge, total, and selected rate-card ID.

## Agent APIs

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/agent/orders` | List assigned deliveries |
| PATCH | `/api/agent/orders/:id/status` | Move to the next valid status or fail delivery |
| PATCH | `/api/agent/availability` | Set Available, Busy, or Offline |
| PATCH | `/api/agent/location` | Save browser geolocation and timestamp |

## Admin APIs

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/admin/orders` | List all orders |
| GET | `/api/admin/customers` | List active customer accounts for admin-created orders |
| GET | `/api/admin/agents` | List live delivery-agent availability and workload |
| GET | `/api/admin/zones` | List configured zones, areas, and postal codes |
| GET | `/api/admin/rate-cards` | List configured rate cards |
| GET | `/api/admin/cod-settings` | List configured COD surcharges |
| GET | `/api/admin/notifications` | List notification-outbox state |
| PATCH | `/api/admin/orders/:id/status` | Override status with a mandatory reason |
| POST | `/api/admin/orders/:id/assign` | Manually assign an eligible agent |
| POST | `/api/admin/orders/:id/auto-assign` | Run the transactional ranking algorithm |

Configuration data is protected by RLS and is intentionally administered through the Supabase dashboard during this assignment's first database deployment. The schema, archive-ready `is_active` fields, and `admin_audit_log` are in place; configuration CRUD can be added as thin admin-only route handlers without changing the database contract.

Order responses include `portalLinks.customer`, `portalLinks.admin`, and `portalLinks.agent`. They are derived from the same order ID; every destination still verifies the caller's role and ownership/assignment.

`POST /api/cron/notifications` is protected by `CRON_SECRET` and processes pending outbox messages.
