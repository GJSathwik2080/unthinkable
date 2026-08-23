import type { CurrentUser } from "@/lib/auth/require-user";
import type { OrderStatus } from "@/lib/types";
import { createAdminClient } from "@/lib/supabase/admin";
import { listOrdersForUser } from "@/lib/services/order-read-service";

const activeStatuses = new Set<OrderStatus>(["ASSIGNED", "PICKED_UP", "IN_TRANSIT", "OUT_FOR_DELIVERY", "RESCHEDULED"]);

function count(orders: { status: OrderStatus }[], predicate: (status: OrderStatus) => boolean) {
  return orders.filter((order) => predicate(order.status)).length;
}

export async function getDashboardForUser(user: CurrentUser) {
  const orders = await listOrdersForUser(user);
  const active = count(orders, (status) => activeStatuses.has(status));
  const delivered = count(orders, (status) => status === "DELIVERED");
  const failed = count(orders, (status) => status === "FAILED");
  const placed = count(orders, (status) => status === "PLACED");
  const metrics = user.role === "ADMIN"
    ? [
        { label: "All orders", value: orders.length, hint: "Across the delivery network", tone: "blue" },
        { label: "Active deliveries", value: active, hint: "Assigned or in progress", tone: "amber" },
        { label: "Awaiting assignment", value: placed, hint: "Dispatch review required", tone: "red" },
        { label: "Delivered", value: delivered, hint: "Completed orders", tone: "green" },
      ]
    : user.role === "DELIVERY_AGENT"
      ? [
          { label: "My deliveries", value: orders.length, hint: "Assigned delivery history", tone: "blue" },
          { label: "In progress", value: active, hint: "Current delivery work", tone: "amber" },
          { label: "Delivered", value: delivered, hint: "Completed by you", tone: "green" },
          { label: "Needs attention", value: failed, hint: "Failed deliveries", tone: "red" },
        ]
      : [
          { label: "My shipments", value: orders.length, hint: "Orders you own", tone: "blue" },
          { label: "In progress", value: active, hint: "Currently moving", tone: "amber" },
          { label: "Delivered", value: delivered, hint: "Completed shipments", tone: "green" },
          { label: "Needs attention", value: failed, hint: "Rescheduling available", tone: "red" },
        ];

  let agent = null;
  if (user.role === "DELIVERY_AGENT") {
    const { data, error } = await createAdminClient()
      .from("agent_profiles")
      .select("availability, current_latitude, current_longitude, location_updated_at")
      .eq("user_id", user.id)
      .maybeSingle();
    if (error) throw new Error(error.message);
    agent = data;
  }
  return { metrics, orders: orders.slice(0, 8), agent };
}

export async function listAdminAgents() {
  const db = createAdminClient();
  const [{ data: agents, error: agentError }, { data: activeAssignments, error: assignmentError }] = await Promise.all([
    db.from("agent_profiles").select("user_id, availability, current_latitude, current_longitude, location_updated_at, profiles!agent_profiles_user_id_fkey(full_name), zones!agent_profiles_home_zone_id_fkey(name, code)").order("updated_at", { ascending: false }),
    db.from("delivery_assignments").select("agent_id").eq("is_active", true),
  ]);
  if (agentError) throw new Error(agentError.message);
  if (assignmentError) throw new Error(assignmentError.message);
  const workloads = new Map<string, number>();
  for (const assignment of activeAssignments ?? []) workloads.set(assignment.agent_id, (workloads.get(assignment.agent_id) ?? 0) + 1);
  return (agents ?? []).map((agent) => ({
    id: agent.user_id,
    name: (agent.profiles as unknown as { full_name: string } | null)?.full_name ?? "Unnamed agent",
    availability: agent.availability,
    zone: (agent.zones as unknown as { name: string; code: string } | null) ?? null,
    locationUpdatedAt: agent.location_updated_at,
    hasLocation: agent.current_latitude !== null && agent.current_longitude !== null,
    activeJobs: workloads.get(agent.user_id) ?? 0,
  }));
}

export async function listAdminCustomers() {
  const { data, error } = await createAdminClient()
    .from("profiles")
    .select("id, full_name")
    .eq("role", "CUSTOMER")
    .eq("is_active", true)
    .order("full_name");
  if (error) throw new Error(error.message);
  return data ?? [];
}

export async function listZones() {
  const { data, error } = await createAdminClient()
    .from("zones")
    .select("id, name, code, is_active, service_areas(id, name, is_active, service_area_postal_codes(postal_code, is_active))")
    .order("name");
  if (error) throw new Error(error.message);
  return data ?? [];
}

export async function listRateCards() {
  const { data, error } = await createAdminClient()
    .from("rate_cards")
    .select("id, order_type, base_weight_grams, base_charge_minor, additional_step_grams, additional_step_charge_minor, effective_from, effective_to, is_active, pickup:zones!rate_cards_pickup_zone_id_fkey(name, code), drop:zones!rate_cards_drop_zone_id_fkey(name, code)")
    .order("effective_from", { ascending: false });
  if (error) throw new Error(error.message);
  return data ?? [];
}

export async function listCodSettings() {
  const { data, error } = await createAdminClient().from("cod_surcharges").select("order_type, surcharge_minor, is_active").order("order_type");
  if (error) throw new Error(error.message);
  return data ?? [];
}

export async function listNotifications() {
  const { data, error } = await createAdminClient()
    .from("notification_outbox")
    .select("id, channel, recipient, status, attempt_count, last_error, created_at, order_events!inner(status, orders!inner(tracking_number))")
    .order("created_at", { ascending: false })
    .limit(100);
  if (error) throw new Error(error.message);
  return data ?? [];
}
