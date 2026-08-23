export type UserRole = "CUSTOMER" | "ADMIN" | "DELIVERY_AGENT";
export type OrderType = "B2B" | "B2C";
export type PaymentType = "PREPAID" | "COD";
export type OrderStatus = "PLACED" | "ASSIGNED" | "PICKED_UP" | "IN_TRANSIT" | "OUT_FOR_DELIVERY" | "DELIVERED" | "FAILED" | "RESCHEDULED";

export interface Money { amountMinor: number; currency: string; }
export interface Zone { id: string; name: string; code: string; }
export interface QuoteInput {
  pickupPostalCode: string; dropPostalCode: string; lengthCm: number; breadthCm: number;
  heightCm: number; actualWeightKg: number; orderType: OrderType; paymentType: PaymentType;
}
export interface Quote {
  pickupZone: Zone; dropZone: Zone; movementType: "INTRA_ZONE" | "INTER_ZONE";
  actualWeightGrams: number; volumetricWeightGrams: number; billableWeightGrams: number;
  baseCharge: Money; additionalWeightCharge: Money; codSurcharge: Money; totalCharge: Money;
  rateCardId: string;
}
export interface TrackingEvent { status: OrderStatus; timestamp: string; actor: string; note: string; }
export interface OrderPortalLinks { customer: string; admin: string; agent: string; }
export interface OrderSummary {
  id: string; trackingNumber: string; customerId: string; status: OrderStatus; orderType: OrderType;
  paymentType: PaymentType; scheduledDeliveryDate: string | null; createdAt: string;
  pickup: string; drop: string; pickupZoneId: string | null; dropZoneId: string | null;
  totalChargeMinor: number; currency: string; agent: string | null; assignedAgentId: string | null;
  portalLinks: OrderPortalLinks;
}
export interface OrderTimelineEvent {
  id: string; status: OrderStatus; actor: string; actorRole: string; note: string | null;
  isOverride: boolean; createdAt: string;
}
export interface OrderDetail extends OrderSummary { timeline: OrderTimelineEvent[]; }
