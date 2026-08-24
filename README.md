# 🚚 Last-Mile Delivery Tracker

A comprehensive, production-ready last-mile delivery management platform featuring dynamic rate calculation, intelligent agent assignment, immutable order tracking, failed delivery handling with rescheduling, and role-based portals for **Customers**, **Admins (Operations)**, and **Delivery Agents**.

---

## 🌐 Live Deployment & Repository

* **Live Application URL:** [https://unthinkable-vbmf.vercel.app/](https://unthinkable-vbmf.vercel.app/)
* **GitHub Repository:** [https://github.com/GJSathwik2080/unthinkable](https://github.com/GJSathwik2080/unthinkable) (Branch: `main`)

---

## 🔑 Demo Access & Login Credentials

All 3 roles support instant one-click demo login on their respective login screens, or manual authentication with the credentials below:

| Role | Portal URL | Demo Email | Demo Password |
| :--- | :--- | :--- | :--- |
| **Customer** | `/login/customer` | `guest.customer@example.com` | `GuestCustomerPassword123!` |
| **Admin / Operations** | `/login/admin` | `guest.admin@example.com` | `GuestAdminPassword123!` |
| **Delivery Agent** | `/login/agent` | `guest.agent@example.com` | `GuestAgentPassword123!` |

---

## 📋 Core Features & Requirements Implemented

### 1. Dynamic Rate Calculation Engine (No Hardcoding)
* **Zone Detection:** Automatic resolution of 6-digit Indian postal codes into service areas and delivery zones (with fallback to `UNIV` Universal zone).
* **Volumetric Weight Calculation:** Calculated using the standard logistics formula:
* **Volumetric Weight (kg):** `(L x B x H) / 5000`
* **Billable Weight:** Higher of Actual Weight vs. Volumetric Weight, rounded up to the nearest configured increment (e.g. 500g steps).
* **Directional Rate Cards:** Dynamically selects active rate cards based on Pickup Zone ➔ Drop Zone, separated by order type (**B2B** and **B2C**).
* **COD Surcharges:** Applies configurable Cash-on-Delivery surcharge when payment method is `COD`.
* **Live Pre-Confirmation Quote:** Itemized breakdown (Base Charge, Additional Weight Charge, COD Surcharge, Total) presented before order confirmation.

### 2. Intelligent Agent Assignment Engine
* **Manual Assignment:** Admins can pick any eligible, active agent from a filtered dropdown list.
* **Intelligent Auto-Assignment:**
  1. Identifies available agents in the pickup zone.
  2. Ranks candidate agents by proximity using **Haversine Distance** calculation between agent GPS coordinates and the pickup area centroid.
  3. Uses zone availability and least-recent assignment as fallback if GPS coordinates are unavailable.
  4. Atomic PostgreSQL transaction ensures zero race conditions during simultaneous assignment requests.

### 3. Immutable Order Status Lifecycle
* Status transition state machine:
  * `PLACED` ➔ `ASSIGNED` ➔ `PICKED_UP` ➔ `IN_TRANSIT` ➔ `OUT_FOR_DELIVERY` ➔ `DELIVERED`
  * `OUT_FOR_DELIVERY` ➔ `FAILED` ➔ `RESCHEDULED` ➔ `ASSIGNED`
* **Immutable Audit Trail:** Every status transition writes an immutable event into `order_events` with timestamp, actor UUID, role, notes, and failure reasons.
* **Admin Overrides:** Admins can override statuses when required with mandatory audit trail logging.

### 4. Failed Delivery & Rescheduling Workflow
* When a delivery fails, the agent records the specific failure reason.
* The customer receives immediate notification and can choose a new scheduled delivery date on their tracking screen.
* Rescheduling opens a new delivery attempt and automatically releases the prior assignment, making the order eligible for agent reassignment.

### 5. Multi-Channel Notification Outbox
* Outbox pattern guarantees message delivery via **Resend (Email)** and **Twilio (SMS)**.
* Includes background cron worker endpoint `/api/cron/notifications` for automated retry and status delivery.

### 6. Frictionless Authentication
* Phone numbers are optional during signup.
* Email confirmation is disabled by default for faster onboarding.
* Distinct, easy-to-find role login portals from the homepage.

---

## 🏗️ System Design Overview (<800 Words)

### Architecture
LastMile uses Next.js (App Router) combined with Supabase PostgreSQL as a transactional backend. Business logic, state transitions, and pricing computations are offloaded to PostgreSQL stored functions (`calculate_order_quote`, `create_order`, `transition_order_status`, `auto_assign_delivery_agent`), guaranteeing ACID compliance and zero race conditions.

```
┌────────────────────────────────────────────────────────┐
│                   Next.js App Router                   │
│   /customer/*         /admin/*             /agent/*    │
│  (Customer Portal)  (Operations Console) (Agent Screen)│
└──────────────────────────┬─────────────────────────────┘
                           │ (Server Actions & Route Handlers)
                           ▼
┌────────────────────────────────────────────────────────┐
│               Supabase PostgreSQL Engine               │
│  • Row-Level Security (RLS) policies per Role          │
│  • Rate calculation & zone mapping RPC functions       │
│  • Haversine distance-ranked agent auto-assignment     │
│  • Immutable order_events audit trail                  │
│  • Notification outbox queue (Email/SMS)               │
└────────────────────────────────────────────────────────┘
```

### Rate Calculation & Zone Resolution
1. The client passes postal codes, L x B x H in cm, actual weight in kg, order type (`B2B`/`B2C`), and payment type (`PREPAID`/`COD`).
2. `lookup_postal_code_zone` maps 6-digit codes to their service zone (`NORTH`, `SOUTH`, `WEST`, or `UNIV`).
3. Volumetric weight is calculated using the database-stored divisor (`5000`).
4. Billable weight is calculated: max(actual, volumetric), rounded to 500g increments.
5. The matching directional rate card (`pickup_zone_id` ➔ `drop_zone_id` + `order_type`) supplies the base weight/charge and incremental step charges.
6. If `payment_type = 'COD'`, the active COD surcharge is added. The confirmed calculation is frozen into `order_pricing_snapshots`.

### Auto-Assignment Logic
1. Filters active delivery agents with status `AVAILABLE`.
2. Prioritizes agents assigned to the pickup zone.
3. If real-time agent GPS coordinates and service area coordinates exist, candidates are sorted using the Haversine spherical formula:
   `d = 2R * arcsin(sqrt(sin²(Δφ/2) + cos(φ₁) * cos(φ₂) * sin²(Δλ/2)))`
4. The database locks the chosen agent, updates availability to `BUSY`, and creates a `delivery_assignments` row atomically.

### Failed Delivery Handling
1. When an agent marks an order as `FAILED`, they submit a reason string.
2. The attempt closes, the agent is freed (`AVAILABLE`), and an outbox notification is enqueued for the customer.
3. The customer accesses `/customer/orders/:id` and selects a rescheduled date.
4. Rescheduling updates the order status to `RESCHEDULED`, logs the event, and puts the order back into the assignment queue for the next delivery window.

---

## 🛠️ Technology Stack

| Component | Technology |
| :--- | :--- |
| **Framework** | Next.js 16 (App Router, Turbopack, React 19, TypeScript) |
| **Styling** | Vanilla Modern CSS (Responsive, Glassmorphism, CSS Grid) |
| **Database & Auth** | Supabase (PostgreSQL with RLS, Supabase Auth) |
| **Validation** | Zod Schema Validation |
| **Unit Testing** | Vitest (12/12 passing unit & domain tests) |
| **Deployment** | Vercel Serverless Edge Platform |

---

## 🗄️ Database Schema Summary

* **`profiles` / `agent_profiles`**: Role-based profiles linked directly to Supabase Auth UUIDs (`CUSTOMER`, `ADMIN`, `DELIVERY_AGENT`), with home zones, current coordinates, and availability state (`AVAILABLE`, `BUSY`, `OFFLINE`).
* **`zones`, `service_areas`, `service_area_postal_codes`**: Multi-tier geographic hierarchy mapping Indian PIN codes to operational zones.
* **`pricing_settings`, `rate_cards`, `cod_surcharges`**: Configurable rate matrices for intra/inter-zone B2B/B2C shipments and COD fees.
* **`orders`, `order_addresses`, `order_pricing_snapshots`**: Master order headers, normalized pickup/drop coordinates & contact information, and immutable pricing records.
* **`delivery_attempts`, `delivery_assignments`, `order_events`**: Multi-attempt lifecycle tracker, assignment allocations, and append-only audit trail.
* **`notification_outbox`, `admin_audit_log`**: Transactional outbox pattern for customer communications and admin override logs.

---

## 💻 Local Development Setup

### 1. Clone the repository
```bash
git clone https://github.com/GJSathwik2080/unthinkable.git
cd unthinkable
```

### 2. Install dependencies
```bash
npm install
```

### 3. Configure environment variables
Create a `.env.local` file in the root directory:
```ini
APP_ENV=development

NEXT_PUBLIC_SUPABASE_URL=https://hhqvchvccybxuaxhjmyy.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=your-supabase-anon-key
SUPABASE_SECRET_KEY=your-supabase-service-role-key

ENABLE_GUEST_LOGIN=true
GUEST_CUSTOMER_EMAIL=guest.customer@example.com
GUEST_CUSTOMER_PASSWORD=GuestCustomerPassword123!
GUEST_ADMIN_EMAIL=guest.admin@example.com
GUEST_ADMIN_PASSWORD=GuestAdminPassword123!
GUEST_AGENT_EMAIL=guest.agent@example.com
GUEST_AGENT_PASSWORD=GuestAgentPassword123!

CRON_SECRET=local-development-secret-key
```

### 4. Run tests and linting
```bash
npm test        # Runs unit test suite
npm run lint    # Runs ESLint code quality checks
```

### 5. Start the development server
```bash
npm run dev
```
Open [http://localhost:3000](http://localhost:3000) in your browser.

---

## 🧪 Verification & Acceptance Test Steps

1. **Customer Order Creation:**
   * Sign in as Customer (`/login/customer` ➔ One-click demo login).
   * Click **Create order**, enter pickup PIN `535002` and drop PIN `600127`, dimensions 20 x 15 x 10 cm, weight 2.5 kg.
   * Click **Calculate delivery charge** to see the itemized breakdown.
   * Fill recipient contact details and click **Confirm order**.
2. **Admin Assignment:**
   * Sign in as Admin (`/login/admin` ➔ One-click demo login).
   * Open the new order and either select an agent from the dropdown or click **Auto assign**.
3. **Agent Delivery Journey:**
   * Sign in as Delivery Agent (`/login/agent` ➔ One-click demo login).
   * Progress the delivery: **Mark Picked Up** ➔ **Mark In Transit** ➔ **Mark Out For Delivery** ➔ **Mark Delivered** (or **Report failed delivery**).
4. **Reschedule Verification:**
   * If marked Failed, switch back to Customer to see the updated timeline and click **Reschedule delivery**.
