import { createAdminClient } from "@/lib/supabase/admin";
import type { CurrentUser } from "@/lib/auth/require-user";
import { buildOrderPortalLinks } from "@/lib/order-links";
import type { OrderDetail, OrderStatus, OrderSummary, OrderType, PaymentType } from "@/lib/types";

type Row = Record<string, unknown>;

function list(value: unknown): Row[] {
  return Array.isArray(value) ? value as Row[] : [];
}

function first(value: unknown): Row | null {
  return Array.isArray(value) ? (value[0] as Row | undefined) ?? null : (value as Row | null);
}

function dateOnly(value: unknown) {
  return value ? new Date(String(value)).toISOString().slice(0, 10) : null;
}

function toOrderSummary(row: Row): OrderSummary {
  const addresses = list(row.order_addresses);
  const pickup = addresses.find((address) => address.address_type === "PICKUP");
  const drop = addresses.find((address) => address.address_type === "DROP");
  const pricing = first(row.order_pricing_snapshots);
  const attempts = list(row.delivery_attempts);
  const latestAttempt = [...attempts].sort((a, b) => Number(b.attempt_number) - Number(a.attempt_number))[0];
  const assignments = latestAttempt ? list(latestAttempt.delivery_assignments) : [];
  const assignment = assignments.find((item) => item.is_active) ?? assignments[0];
  const agent = assignment ? first(assignment.profiles) : null;

  const id = String(row.id);
  return {
    id,
    trackingNumber: String(row.tracking_number),
    status: row.current_status as OrderStatus,
    orderType: row.order_type as OrderType,
    paymentType: row.payment_type as PaymentType,
    scheduledDeliveryDate: dateOnly(row.scheduled_delivery_date),
    createdAt: String(row.created_at),
    customerId: String(row.customer_id),
    pickup: pickup?.area_name_snapshot ? String(pickup.area_name_snapshot) : "Pickup",
    drop: drop?.area_name_snapshot ? String(drop.area_name_snapshot) : "Drop",
    pickupZoneId: pickup?.zone_id_snapshot ? String(pickup.zone_id_snapshot) : null,
    dropZoneId: drop?.zone_id_snapshot ? String(drop.zone_id_snapshot) : null,
    totalChargeMinor: Number(pricing?.total_charge_minor ?? 0),
    currency: String(pricing?.currency ?? "INR"),
    agent: agent?.full_name ? String(agent.full_name) : null,
    assignedAgentId: assignment?.agent_id ? String(assignment.agent_id) : null,
    portalLinks: buildOrderPortalLinks(id),
  };
}

const orderSelect = `
  id, tracking_number, customer_id, current_status, order_type, payment_type, scheduled_delivery_date, created_at,
  order_addresses(address_type, recipient_name, recipient_phone, address_line_1, address_line_2, area_name_snapshot, postal_code_snapshot, zone_id_snapshot),
  order_pricing_snapshots(total_charge_minor, currency, actual_weight_grams, volumetric_weight_grams, billable_weight_grams, base_charge_minor, additional_charge_minor, cod_charge_minor),
  delivery_attempts(id, attempt_number, scheduled_date, status, failure_reason, created_at, delivery_assignments(id, agent_id, is_active, method, profiles!delivery_assignments_agent_id_fkey(full_name)))
`;

export async function listOrdersForUser(user: CurrentUser) {
  const db = createAdminClient();
  let orderIds: string[] | null = null;

  if (user.role === "DELIVERY_AGENT") {
    const { data, error } = await db
      .from("delivery_assignments")
      .select("attempt_id, delivery_attempts!inner(order_id)")
      .eq("agent_id", user.id);
    if (error) throw new Error(error.message);
    orderIds = [...new Set((data ?? []).map((item) => {
      const attempt = first(item.delivery_attempts);
      return attempt ? String(attempt.order_id) : "";
    }).filter(Boolean))];
    if (!orderIds.length) return [];
  }

  let query = db.from("orders").select(orderSelect).order("created_at", { ascending: false });
  if (user.role === "CUSTOMER") query = query.eq("customer_id", user.id);
  if (orderIds) query = query.in("id", orderIds);
  const { data, error } = await query;
  if (error) throw new Error(error.message);
  return (data ?? []).map((row) => toOrderSummary(row as Row));
}

export async function getOrderForUser(orderId: string, user: CurrentUser): Promise<OrderDetail | null> {
  const orders = await listOrdersForUser(user);
  const summary = orders.find((order) => order.id === orderId);
  if (!summary) return null;

  const db = createAdminClient();
  const { data: events, error } = await db
    .from("order_events")
    .select("id, status, actor_role, note, is_override, created_at, profiles!order_events_actor_user_id_fkey(full_name)")
    .eq("order_id", orderId)
    .order("created_at");
  if (error) throw new Error(error.message);

  return {
    ...summary,
    timeline: (events ?? []).map((event) => ({
      id: event.id,
      status: event.status,
      actor: first(event.profiles)?.full_name ?? event.actor_role,
      actorRole: event.actor_role,
      note: event.note,
      isOverride: event.is_override,
      createdAt: event.created_at,
    })),
  };
}

export async function getTrackingNumber(orderId: string) {
  const db = createAdminClient();
  const { data, error } = await db.from("orders").select("tracking_number").eq("id", orderId).single();
  if (error) throw new Error(error.message);
  return data.tracking_number;
}
