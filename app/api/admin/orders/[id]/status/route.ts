import { z } from "zod";
import { fail, ok } from "@/lib/api-response";
import { requireUser } from "@/lib/auth/require-user";
import { createAdminClient } from "@/lib/supabase/admin";

const adminStatusSchema = z.object({
  status: z.enum(["PLACED", "ASSIGNED", "PICKED_UP", "IN_TRANSIT", "OUT_FOR_DELIVERY", "DELIVERED", "FAILED", "RESCHEDULED"]),
  reason: z.string().trim().min(3).max(500),
  failureReason: z.string().trim().min(3).max(500).optional(),
});

export async function PATCH(request: Request, context: { params: Promise<{ id: string }> }) {
  const { user, response } = await requireUser(["ADMIN"]);
  if (!user) return response!;
  const payload = adminStatusSchema.safeParse(await request.json());
  if (!payload.success) return fail("INVALID_INPUT", "An override reason and valid status are required.", 422, payload.error.flatten().fieldErrors);
  try {
    const { id } = await context.params;
    const { error } = await createAdminClient().rpc("transition_order_status", {
      p_order_id: id, p_next_status: payload.data.status, p_actor_user_id: user.id,
      p_note: payload.data.reason, p_failure_reason: payload.data.failureReason ?? null, p_is_override: true,
    });
    if (error) throw new Error(error.message);
    return ok({ orderId: id, status: payload.data.status });
  } catch (error) { return fail("OVERRIDE_FAILED", error instanceof Error ? error.message : "Unable to override this order status.", 422); }
}
