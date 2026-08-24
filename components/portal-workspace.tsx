"use client";

import Link from "next/link";
import { FormEvent, useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { roleLabels } from "@/lib/auth/roles";
import { formatMoney, formatWeight } from "@/lib/domain/format";
import type { Money, OrderDetail, OrderStatus, OrderSummary, Quote, UserRole } from "@/lib/types";

type Page = "dashboard" | "orders" | "new-order" | "order-detail" | "agents" | "zones" | "rate-cards" | "cod-settings" | "notifications" | "profile";
type Remote<T> = { data: T | null; loading: boolean; error: string; reload: () => void };
type Dashboard = { metrics: Array<{ label: string; value: number; hint: string; tone: string }>; orders: OrderSummary[]; agent: { availability: string; location_updated_at: string | null } | null };
type Agent = { id: string; name: string; availability: "AVAILABLE" | "BUSY" | "OFFLINE"; zone: { name: string; code: string } | null; locationUpdatedAt: string | null; hasLocation: boolean; activeJobs: number };
type Customer = { id: string; full_name: string };
type CurrentUser = { id: string; email: string; fullName: string; role: UserRole };

const statusLabels: Record<OrderStatus, string> = {
  PLACED: "Pending assignment", ASSIGNED: "Assigned", PICKED_UP: "Picked up", IN_TRANSIT: "In transit",
  OUT_FOR_DELIVERY: "Out for delivery", DELIVERED: "Delivered", FAILED: "Failed", RESCHEDULED: "Rescheduled",
};

const roleKey: Record<UserRole, "customer" | "admin" | "agent"> = { CUSTOMER: "customer", ADMIN: "admin", DELIVERY_AGENT: "agent" };

function api<T>(url: string, init?: RequestInit): Promise<T> {
  return fetch(url, init).then(async (response) => {
    const body = await response.json();
    if (!response.ok) throw new Error(body.error?.message ?? "The request failed.");
    return body.data as T;
  });
}

function useRemote<T>(url: string | null): Remote<T> {
  const [data, setData] = useState<T | null>(null);
  const [loading, setLoading] = useState(Boolean(url));
  const [error, setError] = useState("");
  const load = useCallback(() => {
    if (!url) return;
    setLoading(true); setError("");
    void api<T>(url).then(setData).catch((cause) => setError(cause instanceof Error ? cause.message : "Unable to load data.")).finally(() => setLoading(false));
  }, [url]);
  useEffect(() => { void Promise.resolve().then(load); }, [load]);
  return { data, loading, error, reload: load };
}

function StatusBadge({ status }: { status: OrderStatus | "AVAILABLE" | "BUSY" | "OFFLINE" }) {
  const text = status in statusLabels ? statusLabels[status as OrderStatus] : status.charAt(0) + status.slice(1).toLowerCase();
  return <span className={`status status-${status.toLowerCase().replaceAll("_", "-")}`}>{text}</span>;
}

function State({ loading, error, empty, children }: { loading: boolean; error: string; empty: boolean; children: React.ReactNode }) {
  if (loading) return <div className="empty-state">Loading live data…</div>;
  if (error) return <div className="empty-state">{error}</div>;
  if (empty) return <div className="empty-state">No records are available yet.</div>;
  return <>{children}</>;
}

function navigation(role: UserRole) {
  if (role === "CUSTOMER") return [["dashboard", "Dashboard", "/customer/dashboard"], ["new-order", "Create order", "/customer/orders/new"], ["orders", "My orders", "/customer/orders"], ["profile", "Profile", "/customer/profile"]] as const;
  if (role === "ADMIN") return [["dashboard", "Dashboard", "/admin/dashboard"], ["orders", "Orders", "/admin/orders"], ["agents", "Agents", "/admin/agents"], ["zones", "Zones & areas", "/admin/zones"], ["rate-cards", "Rate cards", "/admin/rate-cards"], ["cod-settings", "COD settings", "/admin/cod-settings"], ["notifications", "Notification log", "/admin/notifications"]] as const;
  return [["dashboard", "Dashboard", "/agent/dashboard"], ["orders", "My deliveries", "/agent/orders"], ["profile", "Availability", "/agent/profile"]] as const;
}

function Shell({ role, page, children }: { role: UserRole; page: Page; children: React.ReactNode }) {
  const user = useRemote<CurrentUser>("/api/auth/me");
  const router = useRouter();
  const signOut = async () => { await fetch("/api/auth/logout", { method: "POST" }); router.push("/"); router.refresh(); };
  return <div className="app-shell"><aside className="sidebar"><Link href="/" className="side-brand"><span>LM</span><strong>LastMile</strong></Link><p className="side-eyebrow">{role === "ADMIN" ? "Operations console" : role === "CUSTOMER" ? "Customer portal" : "Agent workspace"}</p><nav>{navigation(role).map(([key, label, href]) => <Link key={key} href={href} className={`nav-link ${page === key ? "active" : ""}`}><i />{label}</Link>)}</nav><div className="side-foot"><button className="logout" type="button" onClick={() => void signOut()}>Sign out</button></div></aside><section className="app-main"><header className="topbar"><div className="mobile-brand">LM</div><div className="topbar-spacer" /><div className="user-chip"><span className="avatar">{user.data?.fullName.slice(0, 2).toUpperCase() ?? "…"}</span><div><b>{user.data?.fullName ?? "Loading profile"}</b><small>{roleLabels[role]}</small></div></div></header><main className="content">{children}</main></section></div>;
}

function PageTitle({ eyebrow, title, action }: { eyebrow: string; title: string; action?: React.ReactNode }) {
  return <div className="page-title"><div><p>{eyebrow}</p><h1>{title}</h1></div>{action}</div>;
}

function OrdersTable({ role, orders, compact = false }: { role: UserRole; orders: OrderSummary[]; compact?: boolean }) {
  const entries = compact ? orders.slice(0, 5) : orders;
  return <div className="table-wrap"><table><thead><tr><th>Tracking ID</th><th>Route</th><th>Scheduled</th><th>Agent</th><th>Status</th><th>Charge</th></tr></thead><tbody>{entries.map((order) => <tr key={order.id}><td><Link className="tracking-link" href={order.portalLinks[roleKey[role]]}>{order.trackingNumber}</Link><small>{order.orderType} · {order.paymentType}</small></td><td>{order.pickup}<span className="route-arrow">→</span>{order.drop}</td><td>{order.scheduledDeliveryDate ?? "Not scheduled"}</td><td>{order.agent ?? <span className="muted">Unassigned</span>}</td><td><StatusBadge status={order.status} /></td><td>{formatMoney({ amountMinor: order.totalChargeMinor, currency: order.currency })}</td></tr>)}</tbody></table></div>;
}

function DashboardPage({ role }: { role: UserRole }) {
  const dashboard = useRemote<Dashboard>("/api/dashboard");
  const title = role === "ADMIN" ? "Operations overview" : role === "CUSTOMER" ? "Your shipment overview" : "My delivery overview";
  return <><PageTitle eyebrow="Live data" title={title} action={role === "CUSTOMER" ? <Link className="button primary" href="/customer/orders/new">Create order</Link> : role === "ADMIN" ? <Link className="button primary" href="/admin/orders">Open orders</Link> : <Link className="button primary" href="/agent/orders">Open deliveries</Link>} /><State loading={dashboard.loading} error={dashboard.error} empty={!dashboard.data}>{dashboard.data && <><section className="metric-grid">{dashboard.data.metrics.map((metric) => <article className="metric" key={metric.label}><span className={`metric-dot ${metric.tone}`} /><p>{metric.label}</p><strong>{metric.value}</strong><small>{metric.hint}</small></article>)}</section>{role === "DELIVERY_AGENT" && dashboard.data.agent && <section className="panel"><p className="section-kicker">Availability</p><h2><StatusBadge status={dashboard.data.agent.availability as "AVAILABLE" | "BUSY" | "OFFLINE"} /></h2><p className="muted-copy">Location update: {dashboard.data.agent.location_updated_at ? new Date(dashboard.data.agent.location_updated_at).toLocaleString() : "not received"}</p></section>}<section className="panel"><div className="panel-head"><div><p className="section-kicker">Recent orders</p><h2>Shared order activity</h2></div><Link href={role === "CUSTOMER" ? "/customer/orders" : role === "ADMIN" ? "/admin/orders" : "/agent/orders"} className="text-link">View all</Link></div><State loading={false} error="" empty={dashboard.data.orders.length === 0}><OrdersTable role={role} orders={dashboard.data.orders} compact /></State></section></>}</State></>;
}

function OrdersPage({ role }: { role: UserRole }) {
  const endpoint = role === "ADMIN" ? "/api/admin/orders" : role === "DELIVERY_AGENT" ? "/api/agent/orders" : "/api/orders";
  const orders = useRemote<OrderSummary[]>(endpoint);
  const title = role === "ADMIN" ? "All orders" : role === "CUSTOMER" ? "My orders" : "My deliveries";
  const createHref = role === "CUSTOMER" ? "/customer/orders/new" : "/admin/orders/new";
  return <><PageTitle eyebrow="Order workspace" title={title} action={role !== "DELIVERY_AGENT" ? <Link className="button primary" href={createHref}>Create order</Link> : undefined} /><section className="panel"><State loading={orders.loading} error={orders.error} empty={!orders.data || orders.data.length === 0}>{orders.data && <OrdersTable role={role} orders={orders.data} />}</State></section></>;
}

type FormState = { pickupPostalCode: string; dropPostalCode: string; lengthCm: string; breadthCm: string; heightCm: string; actualWeightKg: string; orderType: "B2B" | "B2C"; paymentType: "PREPAID" | "COD" };
const blankOrder: FormState = { pickupPostalCode: "", dropPostalCode: "", lengthCm: "", breadthCm: "", heightCm: "", actualWeightKg: "", orderType: "B2C", paymentType: "PREPAID" };

function OrderForm({ role }: { role: "CUSTOMER" | "ADMIN" }) {
  const [input, setInput] = useState<FormState>(blankOrder); const [customerId, setCustomerId] = useState(""); const [quote, setQuote] = useState<Quote | null>(null); const [message, setMessage] = useState(""); const [error, setError] = useState(""); const [loading, setLoading] = useState(false);
  const customers = useRemote<Customer[]>(role === "ADMIN" ? "/api/admin/customers" : null);
  const update = (key: keyof FormState, value: string) => { setInput((current) => ({ ...current, [key]: value })); setQuote(null); };
  const quotePayload = () => ({ ...input, lengthCm: Number(input.lengthCm), breadthCm: Number(input.breadthCm), heightCm: Number(input.heightCm), actualWeightKg: Number(input.actualWeightKg) });
  async function calculate(event: FormEvent<HTMLFormElement>) { event.preventDefault(); setLoading(true); setMessage(""); setError(""); try { setQuote(await api<Quote>("/api/orders/quote", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(quotePayload()) })); } catch (cause) { setError(cause instanceof Error ? cause.message : "Unable to calculate the quote."); } finally { setLoading(false); } }
  async function confirm(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!quote) return;
    setLoading(true); setError("");
    const formElement = event.currentTarget;
    const form = new FormData(formElement);
    try {
      const normalizePhone = (value: FormDataEntryValue | null) => {
        const digits = String(value ?? "").replace(/\D/g, "");
        return digits.length === 12 && digits.startsWith("91") ? digits.slice(2) : digits;
      };
      const pickupAddressRaw = String(form.get("pickupAddress") ?? "");
      const dropAddressRaw = String(form.get("dropAddress") ?? "");
      const phonePickup = normalizePhone(form.get("pickupPhone"));
      const phoneDrop = normalizePhone(form.get("dropPhone"));

      if (phonePickup.length !== 10) throw new Error("Pickup phone number must be exactly 10 digits.");
      if (phoneDrop.length !== 10) throw new Error("Drop phone number must be exactly 10 digits.");
      if (/^\d+$/.test(pickupAddressRaw.replace(/[\s,.-]+/g, ""))) throw new Error("Pickup address cannot contain only numbers.");
      if (/^\d+$/.test(dropAddressRaw.replace(/[\s,.-]+/g, ""))) throw new Error("Drop address cannot contain only numbers.");

      const payload = {
        ...quotePayload(),
        customerId: role === "ADMIN" ? customerId : undefined,
        pickup: {
          recipientName: String(form.get("pickupRecipientName") ?? ""),
          phone: phonePickup,
          addressLine1: pickupAddressRaw,
          postalCode: input.pickupPostalCode,
        },
        drop: {
          recipientName: String(form.get("dropRecipientName") ?? ""),
          phone: phoneDrop,
          addressLine1: dropAddressRaw,
          postalCode: input.dropPostalCode,
        },
      };
      const created = await api<{ trackingNumber: string }>("/api/orders", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(payload) });
      setMessage(`Order ${created.trackingNumber} was created.`); setQuote(null); formElement.reset(); setInput(blankOrder); setCustomerId("");
    } catch (cause) { setError(cause instanceof Error ? cause.message : "Unable to create the order."); }
    finally { setLoading(false); }
  }
  const money = (value: Money) => formatMoney(value);
  return <div className="order-layout"><form className="form-stack" onSubmit={calculate}><section className="form-card"><div className="form-card-title"><span>1</span><div><h2>Route details</h2><p>Use any valid 6-digit Indian postal code.</p></div></div>{role === "ADMIN" && <label>Customer<State loading={customers.loading} error={customers.error} empty={!customers.data || customers.data.length === 0}><select value={customerId} required onChange={(event) => setCustomerId(event.target.value)}><option value="">Select customer</option>{customers.data?.map((customer) => <option key={customer.id} value={customer.id}>{customer.full_name}</option>)}</select></State></label>}<div className="field-grid"><label>Pickup postal code<input required value={input.pickupPostalCode} onChange={(event) => update("pickupPostalCode", event.target.value)} /></label><label>Drop postal code<input required value={input.dropPostalCode} onChange={(event) => update("dropPostalCode", event.target.value)} /></label></div></section><section className="form-card"><div className="form-card-title"><span>2</span><div><h2>Package details</h2><p>Charges are calculated from live rate cards.</p></div></div><div className="field-grid four"><label>Length (cm)<input required min="1" type="number" value={input.lengthCm} onChange={(event) => update("lengthCm", event.target.value)} /></label><label>Breadth (cm)<input required min="1" type="number" value={input.breadthCm} onChange={(event) => update("breadthCm", event.target.value)} /></label><label>Height (cm)<input required min="1" type="number" value={input.heightCm} onChange={(event) => update("heightCm", event.target.value)} /></label><label>Weight (kg)<input required min="0.01" step="0.01" type="number" value={input.actualWeightKg} onChange={(event) => update("actualWeightKg", event.target.value)} /></label></div><div className="choice-row"><label>Order type<select value={input.orderType} onChange={(event) => update("orderType", event.target.value)}><option value="B2C">B2C</option><option value="B2B">B2B</option></select></label><label>Payment<select value={input.paymentType} onChange={(event) => update("paymentType", event.target.value)}><option value="PREPAID">Prepaid</option><option value="COD">Cash on delivery</option></select></label></div></section><button className="button primary calculate-button" disabled={loading} type="submit">{loading ? "Calculating…" : "Calculate delivery charge"}</button></form><aside className="quote-panel"><p className="section-kicker">Live quote</p><h2>{quote ? "Delivery summary" : "Ready when you are"}</h2>{error && <p className="form-error">{error}</p>}{message && <p className="success-message">{message}</p>}{quote ? <form className="form-stack" onSubmit={confirm}><div className="quote-route"><span>{quote.pickupZone.name}</span><i>→</i><span>{quote.dropZone.name}</span></div><div className="quote-lines"><span>Actual weight<b>{formatWeight(quote.actualWeightGrams)}</b></span><span>Billable weight<b>{formatWeight(quote.billableWeightGrams)}</b></span><span>Delivery<b>{money(quote.baseCharge)}</b></span><span>Additional weight<b>{money(quote.additionalWeightCharge)}</b></span><span>COD<b>{money(quote.codSurcharge)}</b></span></div><div className="quote-total"><span>Total charge</span><strong>{money(quote.totalCharge)}</strong></div><section className="form-card"><label>Pickup contact<input required name="pickupRecipientName" /></label><label>Pickup phone<input required name="pickupPhone" /></label><label>Pickup address<input required name="pickupAddress" /></label><label>Drop contact<input required name="dropRecipientName" /></label><label>Drop phone<input required name="dropPhone" /></label><label>Drop address<input required name="dropAddress" /></label></section><button className="button primary wide" disabled={loading} type="submit">Confirm order</button></form> : <p className="quote-empty">Enter shipment details to request a live itemized quote.</p>}</aside></div>;
}

function nextStatus(status: OrderStatus) { const map: Partial<Record<OrderStatus, OrderStatus>> = { ASSIGNED: "PICKED_UP", PICKED_UP: "IN_TRANSIT", IN_TRANSIT: "OUT_FOR_DELIVERY", OUT_FOR_DELIVERY: "DELIVERED", RESCHEDULED: "ASSIGNED" }; return map[status] ?? null; }

function TrackingDetail({ role, orderId }: { role: UserRole; orderId: string }) {
  const remote = useRemote<OrderDetail>(`/api/orders/${orderId}`); const agents = useRemote<Agent[]>(role === "ADMIN" ? "/api/admin/agents" : null); const [error, setError] = useState(""); const [busy, setBusy] = useState(false);
  const mutate = async (url: string, method: string, body?: unknown) => { setBusy(true); setError(""); try { await api(url, { method, headers: { "Content-Type": "application/json" }, body: body ? JSON.stringify(body) : undefined }); remote.reload(); } catch (cause) { setError(cause instanceof Error ? cause.message : "Unable to update this order."); } finally { setBusy(false); } };
  const order = remote.data; const next = order ? nextStatus(order.status) : null;
  const availableAgents = agents.data?.filter((agent) => agent.availability === "AVAILABLE") ?? [];
  return <State loading={remote.loading} error={remote.error} empty={!order}>{order && <><PageTitle eyebrow="Shipment details" title={order.trackingNumber} action={<StatusBadge status={order.status} />} />{error && <p className="form-error">{error}</p>}<section className="detail-grid"><article className="panel tracking-panel"><div className="panel-head"><div><p className="section-kicker">Tracking timeline</p><h2>Recorded events</h2></div><span className="tracking-route">{order.pickup} → {order.drop}</span></div><State loading={false} error="" empty={order.timeline.length === 0}><div className="timeline">{order.timeline.map((event) => <div className="timeline-item" key={event.id}><i className={event.status === order.status ? "current" : ""} /><div><b>{statusLabels[event.status]}</b><small>{new Date(event.createdAt).toLocaleString()} · {event.actor}</small>{event.note && <p>{event.note}</p>}</div></div>)}</div></State></article><aside className="panel order-summary"><p className="section-kicker">Shipment summary</p><h2>{order.pickup} <i>→</i> {order.drop}</h2><div className="summary-row"><span>Scheduled date</span><b>{order.scheduledDeliveryDate ?? "Not scheduled"}</b></div><div className="summary-row"><span>Assigned agent</span><b>{order.agent ?? "Pending assignment"}</b></div><div className="summary-row total"><span>Total charge</span><b>{formatMoney({ amountMinor: order.totalChargeMinor, currency: order.currency })}</b></div>{role === "DELIVERY_AGENT" && next && <button className="button primary wide" disabled={busy} onClick={() => void mutate(`/api/agent/orders/${order.id}/status`, "PATCH", { status: next })}>Mark {statusLabels[next]}</button>}{role === "DELIVERY_AGENT" && ["ASSIGNED", "PICKED_UP", "IN_TRANSIT", "OUT_FOR_DELIVERY"].includes(order.status) && <button className="button danger wide" disabled={busy} onClick={() => { const failureReason = window.prompt("Why did delivery fail?"); if (failureReason) void mutate(`/api/agent/orders/${order.id}/status`, "PATCH", { status: "FAILED", failureReason }); }}>Report failed delivery</button>}{role === "CUSTOMER" && order.status === "FAILED" && <button className="button primary wide" disabled={busy} onClick={() => { const scheduledDeliveryDate = window.prompt("Reschedule date (YYYY-MM-DD)"); if (scheduledDeliveryDate) void mutate(`/api/orders/${order.id}/reschedule`, "POST", { scheduledDeliveryDate }); }}>Reschedule delivery</button>}{role === "ADMIN" && order.status === "PLACED" && <State loading={agents.loading} error={agents.error} empty={!agents.data}><label>Assign agent<select defaultValue="" disabled={busy || availableAgents.length === 0} onChange={(event) => { if (event.target.value) void mutate(`/api/admin/orders/${order.id}/assign`, "POST", { agentId: event.target.value }); }}>{availableAgents.length === 0 ? <option value="">No available agents</option> : <option value="">Choose available agent</option>}{availableAgents.map((agent) => <option value={agent.id} key={agent.id}>{agent.name}{agent.zone ? ` · ${agent.zone.name}` : ""}</option>)}</select></label><button className="button secondary wide" style={{marginTop: "8px"}} disabled={busy || availableAgents.length === 0} onClick={() => void mutate(`/api/admin/orders/${order.id}/auto-assign`, "POST")}>Auto assign</button></State>}</aside></section></>}</State>;
}

function AdminAgents() { const agents = useRemote<Agent[]>("/api/admin/agents"); return <><PageTitle eyebrow="Delivery network" title="Agents" /><section className="agent-grid"><State loading={agents.loading} error={agents.error} empty={!agents.data || agents.data.length === 0}>{agents.data?.map((agent) => <article className="panel agent-card" key={agent.id}><div className="agent-card-head"><span className="avatar">{agent.name.slice(0, 2).toUpperCase()}</span><StatusBadge status={agent.availability} /></div><h2>{agent.name}</h2><p>{agent.zone ? `${agent.zone.name} (${agent.zone.code})` : "No home zone"}</p><div className="agent-meta"><span><small>Location</small>{agent.hasLocation ? "Available" : "Not shared"}</span><span><small>Last update</small>{agent.locationUpdatedAt ? new Date(agent.locationUpdatedAt).toLocaleString() : "Never"}</span><span><small>Active jobs</small>{agent.activeJobs}</span></div></article>)}</State></section></>;
}

function Zones() { const zones = useRemote<Array<{ id: string; name: string; code: string; is_active: boolean; service_areas: Array<{ id: string; name: string; is_active: boolean; service_area_postal_codes: Array<{ postal_code: string; is_active: boolean }> }> }>>("/api/admin/zones"); return <><PageTitle eyebrow="Serviceability" title="Zones & areas" /><section className="zone-grid"><State loading={zones.loading} error={zones.error} empty={!zones.data || zones.data.length === 0}>{zones.data?.map((zone) => <article className="panel zone-card" key={zone.id}><div className="zone-card-head"><span>{zone.code}</span><StatusBadge status={zone.is_active ? "AVAILABLE" : "OFFLINE"} /></div><h2>{zone.name}</h2><div className="area-list">{zone.service_areas.map((area) => <span key={area.id}>{area.name}: {area.service_area_postal_codes.filter((postal) => postal.is_active).map((postal) => postal.postal_code).join(", ") || "No active postal codes"}</span>)}</div></article>)}</State></section></>;
}

function RateCards({ codOnly = false }: { codOnly?: boolean }) { const rates = useRemote<Array<{ id: string; order_type: string; base_weight_grams: number; base_charge_minor: number; additional_step_grams: number; additional_step_charge_minor: number; effective_from: string; is_active: boolean; pickup: { name: string } | null; drop: { name: string } | null }>>(codOnly ? "/api/admin/cod-settings" : "/api/admin/rate-cards"); if (codOnly) return <CodSettings />; return <><PageTitle eyebrow="Pricing engine" title="Rate cards" /><section className="rate-list"><State loading={rates.loading} error={rates.error} empty={!rates.data || rates.data.length === 0}>{rates.data?.map((rate) => <article className="panel rate-card" key={rate.id}><div><p className="section-kicker">{rate.order_type} · {rate.is_active ? "Active" : "Inactive"}</p><h2>{rate.pickup?.name ?? "Unknown"} → {rate.drop?.name ?? "Unknown"}</h2></div><div className="rate-values"><span><small>Base rate</small><b>{formatMoney({ amountMinor: rate.base_charge_minor, currency: "INR" })} / {formatWeight(rate.base_weight_grams)}</b></span><span><small>Additional weight</small><b>{formatMoney({ amountMinor: rate.additional_step_charge_minor, currency: "INR" })} / {formatWeight(rate.additional_step_grams)}</b></span><span><small>Effective from</small><b>{rate.effective_from}</b></span></div></article>)}</State></section></>;
}

function CodSettings() { const settings = useRemote<Array<{ order_type: string; surcharge_minor: number; is_active: boolean }>>("/api/admin/cod-settings"); return <><PageTitle eyebrow="Pricing engine" title="COD settings" /><section className="rate-list"><State loading={settings.loading} error={settings.error} empty={!settings.data || settings.data.length === 0}>{settings.data?.map((setting) => <article className="panel rate-card" key={setting.order_type}><div><p className="section-kicker">{setting.is_active ? "Active" : "Inactive"}</p><h2>{setting.order_type}</h2></div><div className="rate-values"><span><small>COD surcharge</small><b>{formatMoney({ amountMinor: setting.surcharge_minor, currency: "INR" })}</b></span></div></article>)}</State></section></>;
}

function Notifications() { const notices = useRemote<Array<{ id: string; channel: string; recipient: string; status: string; attempt_count: number; created_at: string; order_events: { status: string; orders: { tracking_number: string } | Array<{ tracking_number: string }> } }>>("/api/admin/notifications"); const tracking = (item: NonNullable<typeof notices.data>[number]) => Array.isArray(item.order_events.orders) ? item.order_events.orders[0]?.tracking_number : item.order_events.orders?.tracking_number; return <><PageTitle eyebrow="Delivery assurance" title="Notification log" /><section className="panel"><State loading={notices.loading} error={notices.error} empty={!notices.data || notices.data.length === 0}>{notices.data && <div className="notification-list">{notices.data.map((notice) => <div key={notice.id}><span className="notification-icon">✦</span><b>{tracking(notice) ?? "Order"}</b><p>{notice.order_events.status}<small>{notice.channel} · {new Date(notice.created_at).toLocaleString()}</small></p><em>{notice.status} · attempt {notice.attempt_count}</em></div>)}</div>}</State></section></>;
}

function Profile({ role }: { role: UserRole }) { const user = useRemote<CurrentUser>("/api/auth/me"); const dashboard = useRemote<Dashboard>(role === "DELIVERY_AGENT" ? "/api/dashboard" : null); const [error, setError] = useState(""); const changeAvailability = async () => { const availability = window.prompt("Availability: AVAILABLE, BUSY, or OFFLINE"); if (!availability) return; try { await api("/api/agent/availability", { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ availability }) }); dashboard.reload(); } catch (cause) { setError(cause instanceof Error ? cause.message : "Unable to update availability."); } }; const editName = async () => { if (!user.data) return; const newName = window.prompt("Enter your new full name:", user.data.fullName); if (!newName || newName === user.data.fullName) return; setError(""); try { await api("/api/auth/me", { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ fullName: newName }) }); user.reload(); } catch (cause) { setError(cause instanceof Error ? cause.message : "Unable to update profile."); } }; return <><PageTitle eyebrow="Account" title="Profile" /><section className="profile-grid"><article className="panel"><State loading={user.loading} error={user.error} empty={!user.data}>{user.data && <><div className="panel-head"><div><p className="section-kicker">Personal details</p><h2>{user.data.fullName}</h2></div><button className="button secondary" onClick={() => void editName()}>Edit name</button></div>{error && <p className="form-error" style={{marginTop: "12px"}}>{error}</p>}<div className="profile-details" style={{marginTop: "20px"}}><span><small>Email</small><b>{user.data.email}</b></span><span><small>Role</small><b>{roleLabels[user.data.role]}</b></span></div></>}</State></article>{role === "DELIVERY_AGENT" && <article className="panel"><p className="section-kicker">Work status</p><h2>{dashboard.data?.agent?.availability ?? "Loading…"}</h2><p className="form-error">{error}</p><button className="button secondary" onClick={() => void changeAvailability()}>Change availability</button></article>}</section></>; }

export function PortalWorkspace({ role, page, orderId }: { role: UserRole; page: Page; orderId?: string }) {
  const inner = useMemo(() => {
    if (page === "dashboard") return <DashboardPage role={role} />;
    if (page === "orders") return <OrdersPage role={role} />;
    if (page === "new-order") return <><PageTitle eyebrow="New shipment" title={role === "ADMIN" ? "Create an order for a customer" : "Create a delivery order"} /><OrderForm role={role as "CUSTOMER" | "ADMIN"} /></>;
    if (page === "order-detail" && orderId) return <TrackingDetail role={role} orderId={orderId} />;
    if (page === "agents") return <AdminAgents />;
    if (page === "zones") return <Zones />;
    if (page === "rate-cards") return <RateCards />;
    if (page === "cod-settings") return <CodSettings />;
    if (page === "notifications") return <Notifications />;
    return <Profile role={role} />;
  }, [orderId, page, role]);
  return <Shell role={role} page={page}>{inner}</Shell>;
}
