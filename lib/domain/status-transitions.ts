import type { OrderStatus, UserRole } from "@/lib/types";

const transitions: Record<OrderStatus, OrderStatus[]> = {
  PLACED: ["ASSIGNED"], ASSIGNED: ["PICKED_UP", "FAILED"], PICKED_UP: ["IN_TRANSIT", "FAILED"],
  IN_TRANSIT: ["OUT_FOR_DELIVERY", "FAILED"], OUT_FOR_DELIVERY: ["DELIVERED", "FAILED"],
  DELIVERED: [], FAILED: ["RESCHEDULED"], RESCHEDULED: ["ASSIGNED"],
};

export function canTransition(from: OrderStatus, to: OrderStatus, role: UserRole) {
  if (role === "ADMIN") return from !== to && !["PLACED", "RESCHEDULED"].includes(to);
  if (role !== "DELIVERY_AGENT") return false;
  return transitions[from].includes(to);
}

export function nextAgentStatus(status: OrderStatus): OrderStatus | null {
  const options = transitions[status].filter((item) => item !== "FAILED");
  return options[0] ?? null;
}
