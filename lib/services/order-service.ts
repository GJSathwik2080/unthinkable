import { createAdminClient } from "@/lib/supabase/admin";
import type { Quote, QuoteInput } from "@/lib/types";

function toMoney(amountMinor: number, currency: string) { return { amountMinor, currency }; }

function mapDatabaseQuote(raw: Record<string, unknown>): Quote {
  const currency = String(raw.currency);
  return {
    pickupZone: { id: String(raw.pickupZoneId), name: String(raw.pickupZoneName), code: "" },
    dropZone: { id: String(raw.dropZoneId), name: String(raw.dropZoneName), code: "" },
    movementType: raw.movementType as Quote["movementType"],
    actualWeightGrams: Number(raw.actualWeightGrams),
    volumetricWeightGrams: Number(raw.volumetricWeightGrams),
    billableWeightGrams: Number(raw.billableWeightGrams),
    baseCharge: toMoney(Number(raw.baseChargeMinor), currency),
    additionalWeightCharge: toMoney(Number(raw.additionalChargeMinor), currency),
    codSurcharge: toMoney(Number(raw.codChargeMinor), currency),
    totalCharge: toMoney(Number(raw.totalChargeMinor), currency),
    rateCardId: String(raw.rateCardId),
  };
}

export function isDatabaseConfigured() {
  return Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY && process.env.SUPABASE_SECRET_KEY);
}

export async function getOrderQuote(input: QuoteInput): Promise<Quote> {
  if (!isDatabaseConfigured()) {
    throw new Error("Supabase is not configured. Add the project URL, publishable key, and server secret before requesting a live quote.");
  }
  const db = createAdminClient();
  const { data, error } = await db.rpc("calculate_order_quote", {
    p_pickup_postal_code: input.pickupPostalCode,
    p_drop_postal_code: input.dropPostalCode,
    p_length_cm: input.lengthCm,
    p_breadth_cm: input.breadthCm,
    p_height_cm: input.heightCm,
    p_actual_weight_kg: input.actualWeightKg,
    p_order_type: input.orderType,
    p_payment_type: input.paymentType,
  });
  if (error) throw new Error(error.message);
  return mapDatabaseQuote(data as Record<string, unknown>);
}

export async function createOrder(customerId: string, creatorId: string, payload: Record<string, unknown>, scheduledDeliveryDate?: string) {
  const db = createAdminClient();
  const { data, error } = await db.rpc("create_order", {
    p_customer_id: customerId,
    p_created_by_user_id: creatorId,
    p_order: payload,
    p_scheduled_delivery_date: scheduledDeliveryDate ?? null,
  });
  if (error) throw new Error(error.message);
  return data as string;
}

export async function lookupArea(postalCode: string) {
  if (!isDatabaseConfigured()) {
    throw new Error("Supabase is not configured.");
  }
  const db = createAdminClient();
  const { data, error } = await db
    .from("service_area_postal_codes")
    .select("postal_code, service_areas!inner(id, name, zones!inner(id, name, code))")
    .eq("postal_code", postalCode)
    .eq("is_active", true)
    .maybeSingle();
  if (error) throw new Error(error.message);
  if (!data) {
    const { data: universal, error: universalError } = await db
      .from("service_areas")
      .select("id, zones!inner(id, name, code)")
      .eq("name", "Universal coverage")
      .eq("zones.code", "UNIV")
      .maybeSingle();
    if (universalError || !universal) throw new Error("Universal postal-code coverage is not configured.");
    const zone = universal.zones as unknown as { id: string; name: string; code: string };
    return { postalCode, area: { id: universal.id, name: `Postal code ${postalCode}` }, zone };
  }
  const area = data.service_areas as unknown as { id: string; name: string; zones: { id: string; name: string; code: string } };
  return { postalCode, area: { id: area.id, name: area.name }, zone: area.zones };
}
