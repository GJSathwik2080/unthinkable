import type { UserRole } from "@/lib/types";

const portalPrefixes: Record<UserRole, string> = {
  CUSTOMER: "/customer/orders",
  ADMIN: "/admin/orders",
  DELIVERY_AGENT: "/agent/orders",
};

export function getOrderHref(role: UserRole, orderId: string) {
  return `${portalPrefixes[role]}/${orderId}`;
}

export function buildOrderPortalLinks(orderId: string) {
  return {
    customer: getOrderHref("CUSTOMER", orderId),
    admin: getOrderHref("ADMIN", orderId),
    agent: getOrderHref("DELIVERY_AGENT", orderId),
  };
}
