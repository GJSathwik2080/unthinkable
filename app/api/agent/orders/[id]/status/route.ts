import { fail, ok } from "@/lib/api-response";
import { requireUser } from "@/lib/auth/require-user";
import { createAdminClient } from "@/lib/supabase/admin";
import { statusChangeSchema } from "@/lib/validation/orders";

export async function PATCH(request: Request, context: { params: Promise<{ id: string }> }) {
  const { user, response } = await requireUser(["DELIVERY_AGENT"]);
  if (!user) return response!;
  const payload = statusChangeSchema.safeParse(await request.json());
  if (!payload.success) return fail("INVALID_INPUT", "Choose a valid next status.", 422, payload.error.flatten().fieldErrors);
  try {
    const { id } = await context.params;
    const db = createAdminClient();
    const { error } = await db.rpc("transition_order_status", {
      p_order_id: id,
      p_next_status: payload.data.status,
      p_actor_user_id: user.id,
      p_note: payload.data.note ?? null,
      p_failure_reason: payload.data.failureReason ?? null,
      p_is_override: false,
    });
    if (error) throw new Error(error.message);
    return ok({ orderId: id, status: payload.data.status });
  } catch (error) {
    return fail("STATUS_UPDATE_FAILED", error instanceof Error ? error.message : "Unable to update the delivery status.", 422);
  }
}
