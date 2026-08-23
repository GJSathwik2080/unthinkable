import type { UserRole } from "@/lib/types";

export const userRoles = ["CUSTOMER", "ADMIN", "DELIVERY_AGENT"] as const satisfies readonly UserRole[];
export const loginRoleSlugs = ["customer", "admin", "agent"] as const;
export type LoginRoleSlug = typeof loginRoleSlugs[number];

export const roleLabels: Record<UserRole, string> = {
  CUSTOMER: "Customer",
  ADMIN: "Admin / Operations",
  DELIVERY_AGENT: "Delivery Agent",
};

export const roleDescriptions: Record<UserRole, string> = {
  CUSTOMER: "Create, follow, and reschedule your shipments.",
  ADMIN: "Manage orders, dispatch, configuration, and alerts.",
  DELIVERY_AGENT: "View assigned deliveries and update their progress.",
};

export const roleDashboardPaths: Record<UserRole, string> = {
  CUSTOMER: "/customer/dashboard",
  ADMIN: "/admin/dashboard",
  DELIVERY_AGENT: "/agent/dashboard",
};

export const roleLoginPaths: Record<UserRole, `/login/${LoginRoleSlug}`> = {
  CUSTOMER: "/login/customer",
  ADMIN: "/login/admin",
  DELIVERY_AGENT: "/login/agent",
};

const rolesByLoginSlug: Record<LoginRoleSlug, UserRole> = {
  customer: "CUSTOMER",
  admin: "ADMIN",
  agent: "DELIVERY_AGENT",
};

export function isUserRole(value: unknown): value is UserRole {
  return typeof value === "string" && userRoles.includes(value as UserRole);
}

export function roleFromLoginSlug(value: string): UserRole | null {
  return value in rolesByLoginSlug ? rolesByLoginSlug[value as LoginRoleSlug] : null;
}

export function loginPathForRole(role: UserRole, reason?: "switch-account" | "sign-in") {
  const params = new URLSearchParams();
  if (reason) params.set("reason", reason);
  const query = params.toString();
  return `${roleLoginPaths[role]}${query ? `?${query}` : ""}`;
}
