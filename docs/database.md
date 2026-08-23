# Database Schema

Supabase Auth owns `auth.users`; the application adds the following tables.

| Table | Responsibility |
|---|---|
| `profiles` | App identity, role, phone, active state |
| `zones` | Admin-defined delivery zones |
| `service_areas` | Named areas within a zone and optional centroid |
| `service_area_postal_codes` | One postal code mapped to one service area |
| `pricing_settings` | Divisor, rounding increment, currency |
| `rate_cards` | Directional B2B/B2C base and incremental rates |
| `cod_surcharges` | Fixed COD fee by order type |
| `agent_profiles` | Home zone, availability, latest location |
| `orders` | Shipment owner, creator, lifecycle state, and schedule |
| `order_addresses` | Immutable pickup and drop address snapshots |
| `order_pricing_snapshots` | Immutable configured price calculation snapshot |
| `delivery_attempts` | Assignment and outcome for each delivery attempt |
| `delivery_assignments` | Auto/manual assignment history for attempts |
| `order_events` | Append-only status timeline |
| `notification_outbox` | Email/SMS jobs, provider state, retries |
| `admin_audit_log` | Administrative configuration and override audit trail |

Key rules:

- The same order can have many events, attempts, and released assignments.
- Partial unique indexes enforce one active assignment per agent and per attempt.
- Price components belong to the immutable order-pricing snapshot, not only to a mutable rate card.
- Events cannot be updated or deleted because a trigger rejects mutations.
- RLS uses security-definer authorization helpers so customers see owned orders, agents see assigned orders, and admins see operations data without recursive policies.
- Delivery assignments require a matching `agent_profiles` row, and agent profiles require the `DELIVERY_AGENT` role.
- Admin overrides cannot bypass the active-attempt/assignment requirements for operational delivery states.
- Zones, areas, and rates are deactivated instead of deleted once referenced.

Apply the four numbered migrations in `supabase/migrations/` in ascending order. The legacy draft is retained under `supabase/legacy/` only as historical reference and must not be applied to a new project.
