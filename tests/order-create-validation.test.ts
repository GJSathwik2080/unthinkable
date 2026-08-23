import { describe, expect, it } from "vitest";
import { createOrderSchema } from "../lib/validation/order-create";

const order = {
  pickup: { recipientName: "Asha", phone: "+91 93463 83894", addressLine1: "Peddariv street", postalCode: "520013" },
  drop: { recipientName: "Rahul", phone: "9490366538", addressLine1: "VIT University", postalCode: "600127" },
  lengthCm: 10.1,
  breadthCm: 20.1,
  heightCm: 30.1,
  actualWeightKg: 100,
  orderType: "B2C",
  paymentType: "PREPAID",
};

describe("order contact validation", () => {
  it("accepts normal Indian phone formatting and stores ten digits", () => {
    const parsed = createOrderSchema.parse(order);
    expect(parsed.pickup.phone).toBe("9346383894");
    expect(parsed.drop.phone).toBe("9490366538");
  });
});
