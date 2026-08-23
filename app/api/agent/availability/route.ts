import { fail, ok } from "@/lib/api-response";
import { requireUser } from "@/lib/auth/require-user";
import { createAdminClient } from "@/lib/supabase/admin";
import { agentAvailabilitySchema } from "@/lib/validation/order-create";

export async function PATCH(request: Request) {
  const { user, response } = await requireUser(["DELIVERY_AGENT"]);
  if (!user) return response!;
  const payload = agentAvailabilitySchema.safeParse(await request.json());
  if (!payload.success) return fail("INVALID_INPUT", "Choose a valid availability state.", 422, payload.error.flatten().fieldErrors);
  try {
    const { error } = await createAdminClient().rpc("update_agent_availability", {
      p_agent_user_id: user.id, p_actor_user_id: user.id, p_availability: payload.data.availability,
    });
    if (error) throw new Error(error.message);
    return ok({ availability: payload.data.availability });
  } catch (error) { return fail("AVAILABILITY_UPDATE_FAILED", error instanceof Error ? error.message : "Unable to update availability.", 422); }
}
