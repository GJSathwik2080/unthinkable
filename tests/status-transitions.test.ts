import { describe, expect, it } from "vitest";
import { canTransition } from "../lib/domain/status-transitions";

describe("delivery lifecycle", () => {
  it("allows only the agent's next valid transition", () => {
    expect(canTransition("ASSIGNED", "PICKED_UP", "DELIVERY_AGENT")).toBe(true);
    expect(canTransition("ASSIGNED", "DELIVERED", "DELIVERY_AGENT")).toBe(false);
  });
  it("does not allow a customer to update delivery status", () => {
    expect(canTransition("IN_TRANSIT", "OUT_FOR_DELIVERY", "CUSTOMER")).toBe(false);
  });
  it("allows an admin operational override", () => {
    expect(canTransition("IN_TRANSIT", "DELIVERED", "ADMIN")).toBe(true);
  });
  it("does not treat order creation or rescheduling states as admin overrides", () => {
    expect(canTransition("DELIVERED", "PLACED", "ADMIN")).toBe(false);
    expect(canTransition("IN_TRANSIT", "RESCHEDULED", "ADMIN")).toBe(false);
  });
});
