import { describe, expect, it } from "vitest";
import { loginPathForRole, roleFromLoginSlug, roleLoginPaths } from "../lib/auth/roles";

describe("role login routes", () => {
  it("maps every portal to its dedicated login page", () => {
    expect(roleLoginPaths).toEqual({
      CUSTOMER: "/login/customer",
      ADMIN: "/login/admin",
      DELIVERY_AGENT: "/login/agent",
    });
    expect(roleFromLoginSlug("customer")).toBe("CUSTOMER");
    expect(roleFromLoginSlug("admin")).toBe("ADMIN");
    expect(roleFromLoginSlug("agent")).toBe("DELIVERY_AGENT");
    expect(roleFromLoginSlug("unknown")).toBeNull();
  });

  it("keeps the switch-account reason on the matching login page", () => {
    expect(loginPathForRole("ADMIN", "switch-account")).toBe("/login/admin?reason=switch-account");
  });
});
