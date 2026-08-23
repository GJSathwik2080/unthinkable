import { afterEach, describe, expect, it } from "vitest";
import { areGuestCredentialsConfigured, getGuestCredentials, isGuestLoginEnabled } from "../lib/auth/guest";

const originalEnable = process.env.ENABLE_GUEST_LOGIN;
const guestVariables = [
  "GUEST_CUSTOMER_EMAIL", "GUEST_CUSTOMER_PASSWORD",
  "GUEST_ADMIN_EMAIL", "GUEST_ADMIN_PASSWORD",
  "GUEST_AGENT_EMAIL", "GUEST_AGENT_PASSWORD",
] as const;
const originalGuestVariables = Object.fromEntries(guestVariables.map((name) => [name, process.env[name]]));

afterEach(() => {
  if (originalEnable === undefined) delete process.env.ENABLE_GUEST_LOGIN;
  else process.env.ENABLE_GUEST_LOGIN = originalEnable;
  for (const name of guestVariables) {
    const value = originalGuestVariables[name];
    if (value === undefined) delete process.env[name];
    else process.env[name] = value;
  }
});

describe("guest login", () => {
  it("is enabled only when explicitly configured", () => {
    delete process.env.ENABLE_GUEST_LOGIN;
    expect(isGuestLoginEnabled()).toBe(false);
    process.env.ENABLE_GUEST_LOGIN = "true";
    expect(isGuestLoginEnabled()).toBe(true);
  });

  it("requires fixed credentials for all three guest roles", () => {
    for (const name of guestVariables) delete process.env[name];
    expect(areGuestCredentialsConfigured()).toBe(false);
    process.env.GUEST_CUSTOMER_EMAIL = "customer@example.com";
    process.env.GUEST_CUSTOMER_PASSWORD = "customer-password";
    process.env.GUEST_ADMIN_EMAIL = "admin@example.com";
    process.env.GUEST_ADMIN_PASSWORD = "admin-password";
    process.env.GUEST_AGENT_EMAIL = "agent@example.com";
    process.env.GUEST_AGENT_PASSWORD = "agent-password";
    expect(areGuestCredentialsConfigured()).toBe(true);
    expect(getGuestCredentials("ADMIN")).toEqual({ email: "admin@example.com", password: "admin-password" });
  });
});
