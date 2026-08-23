import { fail, ok } from "@/lib/api-response";
import { getOrderQuote } from "@/lib/services/order-service";
import { quoteSchema } from "@/lib/validation/orders";

export const runtime = "nodejs";

export async function POST(request: Request) {
  try {
    const payload = quoteSchema.safeParse(await request.json());
    if (!payload.success) return fail("INVALID_INPUT", "Enter the required shipment details.", 422, payload.error.flatten().fieldErrors);
    return ok(await getOrderQuote(payload.data));
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unable to calculate quote.";
    return fail("QUOTE_UNAVAILABLE", message, 422);
  }
}
