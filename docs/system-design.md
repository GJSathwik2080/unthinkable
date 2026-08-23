# LastMile System Design

## 1. Architecture

LastMile is a single Next.js App Router application with Customer, Admin / Operations, and Delivery Agent portals. Separate routes share one Supabase PostgreSQL order workflow.

```text
Browser portals
Customer | Admin / Operations | Delivery Agent
                    │
                    ▼
Next.js route handlers and service layer
validation | role checks | workflow commands | live read DTOs
                    │
                    ▼
Supabase Auth + PostgreSQL
RLS | functions | constraints | events | notification outbox
                    │
                    ▼
Optional Resend / Twilio providers and cron retry
```

Portal screens read live APIs and present loading, empty, error, forbidden, and unconfigured states.

## 2. Identity and access control

Supabase Auth owns `auth.users`. The application’s `profiles` table uses that same UUID as its primary key and foreign key. A profile therefore cannot be created for a user that does not exist in Auth.

Profiles have `CUSTOMER`, `ADMIN`, or `DELIVERY_AGENT` roles. Sign-in verifies `profiles.role`; wrong-role users are rejected and sent to the matching login page.

Three fixed guest accounts are bootstrapped once from server-only values. Guest login uses existing accounts, never per-browser temporary users. Health and verification report readiness without secrets.

Row Level Security and security-definer helpers provide database-level protection. Customers see owned orders only, agents see assigned orders only, and admins see operational data. A copied URL cannot bypass those checks.

## 3. Normalized data model

`orders` is central. `order_addresses` stores immutable pickup/drop snapshots and `order_pricing_snapshots` preserves confirmed prices, so later configuration cannot rewrite history.

`delivery_attempts` models each run; `delivery_assignments` records manual, automatic, and rescheduled assignment history; `order_events` is the append-only timeline.

Geography and pricing are normalized separately:

```text
zones → service_areas → service_area_postal_codes
zones + order type → rate_cards
order type → cod_surcharges
```

`agent_profiles` stores home zone, availability, location, and assignment metadata. Partial unique indexes allow only one active assignment per agent and attempt. `admin_audit_log` records overrides; `notification_outbox` persists notification work.

## 4. Zone detection and rate calculation

The quote endpoint accepts postal codes, dimensions, actual weight, B2B/B2C, and Prepaid/COD. It resolves each six-digit code to an active area and zone; valid unmapped codes use `UNIV` Universal service.

The pricing formula is:

```text
volumetric weight = length × breadth × height ÷ configured divisor
billable weight   = round up(max(actual weight, volumetric weight))
total             = base rate + additional-weight steps + COD surcharge
```

The service selects the active directional B2B/B2C rate card. COD is added only for COD orders. Confirmation recalculates server-side and saves the price snapshot.

## 5. Assignment and delivery workflow

Auto-assignment starts with available agents in the pickup zone. When a fresh agent location and a service-area centroid exist, candidates are ranked by Haversine distance. If location data is absent or stale, the fallback is same-zone availability and least-recent assignment. Only when no same-zone candidate exists are another-zone agents considered.

The database function locks the agent, creates an attempt/assignment, marks the order assigned and agent busy, avoiding simultaneous-assignment races.

The normal lifecycle is:

```text
PLACED → ASSIGNED → PICKED_UP → IN_TRANSIT → OUT_FOR_DELIVERY → DELIVERED
                                              └→ FAILED → RESCHEDULED → ASSIGNED
```

Each transition writes immutable actor, role, timestamp, status, and note data. Failure releases its assignment; rescheduling creates a new attempt. Terminal changes close attempts and restore availability atomically.

## 6. Notifications and operations

Status changes create notification-outbox entries in the workflow transaction. The protected cron endpoint retries pending jobs. Resend email and Twilio SMS are optional server-side integrations.

Admin read APIs expose live orders, customers, agents, zones, rate cards, COD settings, and notification status. Configuration is currently maintained in Supabase for the first deployment, while the portal provides visibility into the active configuration.

## 7. Deployment and reliability

Deploy to Vercel, Render, Railway, or another Node.js 22 host after applying migrations. The Supabase URL/publishable key may be browser-visible; secrets remain server-only. `/api/health` reports database, Auth, and guest readiness without leaking keys.
