import type { OrderStatus } from "@/lib/types";

const labels: Record<OrderStatus, string> = {
  PLACED: "has been confirmed", ASSIGNED: "has been assigned to a delivery agent", PICKED_UP: "has been picked up",
  IN_TRANSIT: "is in transit", OUT_FOR_DELIVERY: "is out for delivery", DELIVERED: "has been delivered",
  FAILED: "could not be delivered", RESCHEDULED: "has been rescheduled",
};

export function statusNotification(trackingNumber: string, status: OrderStatus) {
  const text = `Your shipment ${trackingNumber} ${labels[status]}.`;
  return { subject: `LastMile update: ${trackingNumber}`, text };
}
