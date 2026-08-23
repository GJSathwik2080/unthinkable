import type { UserRole } from "@/lib/types";

const guestVariableNames: Record<UserRole, { email: string; password: string }> = {
  CUSTOMER: { email: "GUEST_CUSTOMER_EMAIL", password: "GUEST_CUSTOMER_PASSWORD" },
  ADMIN: { email: "GUEST_ADMIN_EMAIL", password: "GUEST_ADMIN_PASSWORD" },
  DELIVERY_AGENT: { email: "GUEST_AGENT_EMAIL", password: "GUEST_AGENT_PASSWORD" },
};

export function isGuestLoginEnabled() {
  return process.env.ENABLE_GUEST_LOGIN === "true";
}

export class GuestConfigurationError extends Error {}

export function getGuestCredentials(role: UserRole) {
  const names = guestVariableNames[role];
  const email = process.env[names.email];
  const password = process.env[names.password];
  if (!email || !password) throw new GuestConfigurationError(`Guest ${role.toLowerCase()} credentials are not configured.`);
  return { email, password };
}

export function areGuestCredentialsConfigured() {
  try {
    for (const role of ["CUSTOMER", "ADMIN", "DELIVERY_AGENT"] as const) getGuestCredentials(role);
    return true;
  } catch {
    return false;
  }
}
