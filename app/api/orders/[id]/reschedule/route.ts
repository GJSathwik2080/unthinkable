import { fail, ok } from "@/lib/api-response";
import { requireUser } from "@/lib/auth/require-user";
import { createAdminClient } from "@/lib/supabase/admin";
import { rescheduleSchema } from "@/lib/validation/order-create";

export const runtime = "nodejs";

export async function POST(request: Request, context: { params: Promise<{ id: string }> }) {
  const { user, response } = await requireUser(["CUSTOMER", "ADMIN"]);
  if (!user) return response!;
  const payload = rescheduleSchema.safeParse(await request.json());
  if (!payload.success) return fail("INVALID_INPUT", "Choose a valid future delivery date.", 422, payload.error.flatten().fieldErrors);
  try {
    const { id } = await context.params;
    const db = createAdminClient();
    const { data, error } = await db.rpc("reschedule_failed_order", {
      p_order_id: id,
      p_actor_user_id: user.id,
      p_scheduled_date: payload.data.scheduledDeliveryDate,
    });
    if (error) throw new Error(error.message);
    return ok({ assignedAgentId: data ?? null });
  } catch (error) {
    return fail("RESCHEDULE_FAILED", error instanceof Error ? error.message : "Unable to reschedule this order.", 422);
  }
}
