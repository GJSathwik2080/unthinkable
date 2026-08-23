import { fail, ok } from "@/lib/api-response";
import { requireUser } from "@/lib/auth/require-user";
import { createAdminClient } from "@/lib/supabase/admin";
import { agentLocationSchema } from "@/lib/validation/order-create";

export async function PATCH(request: Request) {
  const { user, response } = await requireUser(["DELIVERY_AGENT"]);
  if (!user) return response!;
  const payload = agentLocationSchema.safeParse(await request.json());
  if (!payload.success) return fail("INVALID_INPUT", "Enter valid latitude and longitude values.", 422, payload.error.flatten().fieldErrors);
  try {
    const { error } = await createAdminClient().rpc("update_agent_location", {
      p_agent_user_id: user.id, p_actor_user_id: user.id, p_latitude: payload.data.latitude, p_longitude: payload.data.longitude,
    });
    if (error) throw new Error(error.message);
    return ok({ updated: true });
  } catch (error) { return fail("LOCATION_UPDATE_FAILED", error instanceof Error ? error.message : "Unable to update location.", 422); }
}
