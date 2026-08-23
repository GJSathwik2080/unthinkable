import { describe, expect, it } from "vitest";
import { buildOrderPortalLinks, getOrderHref } from "../lib/order-links";

describe("role-specific order links", () => {
  it("keeps one order id while generating a route for each workspace", () => {
    expect(buildOrderPortalLinks("order-42")).toEqual({
      customer: "/customer/orders/order-42",
      admin: "/admin/orders/order-42",
      agent: "/agent/orders/order-42",
    });
  });

  it("uses the active role's detail route", () => {
    expect(getOrderHref("CUSTOMER", "order-42")).toBe("/customer/orders/order-42");
    expect(getOrderHref("ADMIN", "order-42")).toBe("/admin/orders/order-42");
    expect(getOrderHref("DELIVERY_AGENT", "order-42")).toBe("/agent/orders/order-42");
  });
});
