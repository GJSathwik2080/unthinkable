import { fail, ok } from "@/lib/api-response";
import { requireUser } from "@/lib/auth/require-user";
import { getOrderForUser } from "@/lib/services/order-read-service";

export const runtime = "nodejs";

export async function GET(_: Request, context: { params: Promise<{ id: string }> }) {
  const { user, response } = await requireUser();
  if (!user) return response!;
  try {
    const { id } = await context.params;
    const order = await getOrderForUser(id, user);
    if (!order) return fail("ORDER_NOT_FOUND", "This order was not found or you cannot access it.", 404);
    return ok(order);
  } catch (error) {
    return fail("ORDER_UNAVAILABLE", error instanceof Error ? error.message : "Unable to load this order.", 500);
  }
}
