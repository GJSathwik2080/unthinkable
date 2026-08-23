# LastMile Delivery Tracker

LastMile is a role-based delivery management platform for quoting, creating, assigning, tracking, and completing last-mile shipments. A customer, operations user, and delivery agent work with the same normalized Supabase order record rather than separate copies.

## Features implemented

### Customer portal

- Customer registration and secure sign-in at `/login/customer`.
- Create B2B or B2C orders with pickup/drop postal codes, package dimensions, weight, payment type, contacts, and addresses.
- Receive a live itemized quote before confirmation.
- Use any valid six-digit Indian postal code; unmapped codes use the Universal service zone.
- View owned orders, current status, price, assigned agent, and immutable tracking timeline.
- Reschedule a failed delivery for a future date.

### Admin / Operations portal

- Dedicated sign-in at `/login/admin`.
- View every order and its timeline.
- Create an order on behalf of a selected customer.
- View agents, availability, home zone, location status, and active workload.
- Manually assign an eligible agent or request auto-assignment.
- Override a status with an audit reason where the workflow permits it.
- View zones, service areas, rate cards, COD settings, and notification-outbox activity.

### Delivery Agent portal

- Dedicated sign-in at `/login/agent`.
- View only assigned deliveries.
- Change availability: `AVAILABLE`, `BUSY`, or `OFFLINE`.
- Share location for distance-aware assignment.
- Update deliveries as Picked Up, In Transit, Out for Delivery, Delivered, or Failed.
- Record a failure reason when delivery cannot be completed.

### Shared workflow

- One order ID connects customer, admin, and agent detail routes.
- Role-aware links are `/customer/orders/:id`, `/admin/orders/:id`, and `/agent/orders/:id`; every route enforces access again.
- Logout ends the Supabase session before leaving the portal.
- A wrong-role visit sends the user to the matching dedicated login page.
- Fixed demo accounts can be enabled for demonstrations. They are bootstrapped once; no Auth user is created on every click.
- Screens use live APIs and show loading, empty, forbidden, unconfigured-database, and request-error states instead of sample business activity.

## Technology

| Layer | Implementation |
|---|---|
| Frontend and API | Next.js App Router, TypeScript, React, plain CSS |
| Authentication | Supabase Auth and secure server-managed session cookies |
| Database | Supabase PostgreSQL with Row Level Security (RLS) |
| Validation | Zod; the server recalculates price at confirmation |
| Notifications | Transactional outbox with optional Resend email and Twilio SMS delivery |
| Scheduled retry | Protected notification cron endpoint, compatible with Vercel Cron |

## Local setup

### Prerequisites

- Node.js 22 (`nvm use 22`)
- A Supabase project
- Supabase Project URL, publishable key, and server-only secret key

### 1. Install dependencies

```bash
cd /Users/rushikesh/Desktop/last-mile
nvm use 22
npm ci
```

### 2. Configure environment values

```bash
cp .env.example .env.local
```

Open `.env.local` and provide the Supabase values from **Supabase Dashboard → Project Settings → API**. Never commit `.env.local` or expose `SUPABASE_SECRET_KEY` in browser code.

### 3. Apply the database migrations

In **Supabase Dashboard → SQL Editor**, run every file in `supabase/migrations/` in ascending filename order:

```text
20260821000100_normalized_schema.sql
20260821000200_workflow_functions.sql
20260821000300_rls_and_permissions.sql
20260821000400_seed_development_data.sql
20260823000100_integrity_and_authorization.sql
20260823000200_temporary_guest_sessions.sql
20260823000300_repair_auth_profile_trigger.sql
20260823000400_universal_postal_code_coverage.sql
20260823000500_recreate_auth_profile_trigger.sql
20260823000600_app_managed_auth_profiles.sql
20260823000700_simple_shipment_contact_inputs.sql
```

`20260823000600_app_managed_auth_profiles.sql` removes the stale Auth trigger that can otherwise prevent account/profile creation. The seed migration creates required zone and price configuration, including Universal service; it does not create sample customer/order activity.

### 4. Configure demo accounts

Set the guest values in `.env.local`:

```ini
ENABLE_GUEST_LOGIN=true

GUEST_CUSTOMER_EMAIL=guest.customer@example.com
GUEST_CUSTOMER_PASSWORD=replace-with-a-strong-password

GUEST_ADMIN_EMAIL=guest.admin@example.com
GUEST_ADMIN_PASSWORD=replace-with-a-strong-password

GUEST_AGENT_EMAIL=guest.agent@example.com
GUEST_AGENT_PASSWORD=replace-with-a-strong-password
```

Create/update the three fixed accounts and validate readiness:

```bash
npm run bootstrap:guests
npm run verify:auth
```

The bootstrap script creates Customer, Admin / Operations, and Delivery Agent Auth users; upserts active profiles; and gives the demo agent a Universal-zone agent profile. It is safe to run again. `verify:auth` never prints passwords, keys, or tokens.

### 5. Start the app

```bash
npm run dev
```

Open `http://localhost:3000` or the Network URL printed by Next.js.

Useful pages:

```text
http://localhost:3000/api/health
http://localhost:3000/login
http://localhost:3000/login/customer
http://localhost:3000/login/admin
http://localhost:3000/login/agent
```

`/api/health` returns non-secret database, Auth, and guest-login states such as `reachable`, `unconfigured`, `accounts_missing`, or `ready`.

## Environment reference

Start with [.env.example](.env.example).

| Variable | Required | Purpose |
|---|---:|---|
| `APP_ENV` | Yes | Application environment label |
| `NEXT_PUBLIC_SUPABASE_URL` | Yes | Supabase project URL; browser-safe |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | Yes | Supabase browser publishable key |
| `SUPABASE_SECRET_KEY` | Yes | Server-only Supabase secret/service key |
| `ENABLE_GUEST_LOGIN` | No | Set to `true` to enable demo access |
| `GUEST_*_EMAIL`, `GUEST_*_PASSWORD` | For demo access | Server-only fixed demo credentials |
| `CRON_SECRET` | For notification retry | Protects the cron API route |
| `RESEND_API_KEY`, `EMAIL_FROM` | Optional | Enables email delivery |
| `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_FROM` | Optional | Enables SMS delivery |

## Rate calculation engine

1. The customer or admin supplies postal codes and package details.
2. The server resolves both addresses to active service areas and zones. A valid unmapped six-digit code uses Universal service.
3. Volumetric weight is calculated:

   ```text
   volumetric weight = length × breadth × height ÷ volumetric divisor
   ```

4. Billable weight is the higher of actual and volumetric weight, rounded up to the configured increment.
5. The server selects the active directional rate card for pickup zone, drop zone, and B2B/B2C type.
6. It applies the base rate and additional-weight steps. A COD surcharge applies only to COD orders.
7. The quote is shown before confirmation. Confirmation recalculates on the server and saves an immutable pricing snapshot.

Rate cards, COD surcharges, the volumetric divisor, rounding rules, and zones are database configuration, not hardcoded customer-order data. The admin portal shows live configuration; configuration edits are maintained through Supabase for the initial deployment.

## Assignment, delivery lifecycle, and notifications

### Auto-assignment

The transactional assignment function considers available agents in the pickup zone first. When fresh agent coordinates and an area centroid are available, candidates are ranked using Haversine distance. Otherwise it uses zone availability and least-recent assignment. If no same-zone candidate exists, it considers another zone.

The database transaction locks the selected agent, creates an attempt and assignment, changes the order to assigned, and marks the agent busy. Constraints prevent more than one active assignment for an agent or a delivery attempt.

### Status lifecycle

```text
PLACED → ASSIGNED → PICKED_UP → IN_TRANSIT → OUT_FOR_DELIVERY → DELIVERED
                                              └→ FAILED → RESCHEDULED → ASSIGNED
```

Every valid transition appends an immutable event with timestamp, actor, role, note, and override metadata. Terminal transitions close the attempt, release its assignment, and restore availability atomically.

When delivery fails, the reason is recorded and notification-outbox entries are created. A customer can reschedule; that creates a new delivery attempt and assignment can run again.

## Database design and security

Supabase Auth owns `auth.users`. `profiles.id` is the corresponding Auth UUID, so a profile cannot exist without an Auth user.

| Group | Tables |
|---|---|
| Identity | `profiles`, `agent_profiles` |
| Geography/pricing | `zones`, `service_areas`, `service_area_postal_codes`, `pricing_settings`, `rate_cards`, `cod_surcharges` |
| Orders | `orders`, `order_addresses`, `order_pricing_snapshots` |
| Delivery workflow | `delivery_attempts`, `delivery_assignments`, `order_events` |
| Operations | `notification_outbox`, `admin_audit_log` |

RLS and security-definer authorization helpers enforce these rules:

- Customers read only their own orders.
- Admins access operational data and authorised operational actions.
- Agents read only orders assigned to them.
- A copied order URL does not grant an unrelated user access.
- Agent-role, active-assignment, terminal-transition, append-only-event, and audit-log invariants are database-enforced.

For full table details, see [docs/database.md](docs/database.md).

## API overview

All APIs respond with either:

```json
{ "success": true, "data": {} }
```

or:

```json
{ "success": false, "error": { "code": "ERROR_CODE", "message": "Human-readable message" } }
```

| Area | Important endpoints |
|---|---|
| Authentication | `POST /api/auth/register`, `/api/auth/login`, `/api/auth/guest`, `/api/auth/logout`; `GET /api/auth/me` |
| Customer orders | `POST /api/orders/quote`, `POST/GET /api/orders`, `GET /api/orders/:id`, `GET /api/orders/:id/tracking`, `POST /api/orders/:id/reschedule` |
| Admin operations | `GET /api/admin/orders`, `/customers`, `/agents`, `/zones`, `/rate-cards`, `/cod-settings`, `/notifications`; actions under `/api/admin/orders/:id/*` |
| Agent work | `GET /api/agent/orders`, `PATCH /api/agent/orders/:id/status`, `PATCH /api/agent/availability`, `PATCH /api/agent/location` |
| System | `GET /api/dashboard`, `GET /api/health`, `POST /api/cron/notifications` |

See [docs/api.md](docs/api.md) for request formats, roles, and details.

## Validation and testing

```bash
npm run lint
npm test
npm run build
```

The test suite covers role login paths, fixed guest configuration, order portal-link generation, status transitions, and contact validation.

## Suggested acceptance test

1. Sign in as Customer and create an order.
2. Sign in as Admin / Operations, find the same order, and assign the Delivery Agent.
3. Sign in as Delivery Agent and update delivery status.
4. Refresh Customer and Admin portals; both show the same timeline and status.
5. Mark an order failed, reschedule as Customer, and verify a new attempt is created.

Use separate browser profiles/incognito windows to keep all three sessions open simultaneously.

## Deployment

1. Deploy to Vercel, Render, Railway, or another Node.js 22 host.
2. Add required `.env.example` variables; keep `SUPABASE_SECRET_KEY` server-only.
3. Apply all Supabase migrations before the first deployment.
4. Run `npm run bootstrap:guests` once if public demo access is needed.
5. Configure `CRON_SECRET` and optional Resend/Twilio provider values.
6. Rotate any key that has been pasted in chat, terminal output, an issue, or repository history before production deployment.

## Additional documentation

- [API reference](docs/api.md)
- [Database schema](docs/database.md)
- [System design](docs/system-design.md)
- [Supabase migrations](supabase/migrations)
- [Environment template](.env.example)
