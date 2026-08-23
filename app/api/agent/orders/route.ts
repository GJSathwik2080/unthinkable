import { fail, ok } from "@/lib/api-response";
import { requireUser } from "@/lib/auth/require-user";
import { listOrdersForUser } from "@/lib/services/order-read-service";

export async function GET() {
  const { user, response } = await requireUser(["DELIVERY_AGENT"]);
  if (!user) return response!;
  try { return ok(await listOrdersForUser(user)); }
  catch (error) { return fail("ORDERS_UNAVAILABLE", error instanceof Error ? error.message : "Unable to load deliveries.", 500); }
}
