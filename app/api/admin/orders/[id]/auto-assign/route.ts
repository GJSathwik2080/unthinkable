import { fail, ok } from "@/lib/api-response";
import { requireUser } from "@/lib/auth/require-user";
import { createAdminClient } from "@/lib/supabase/admin";

export async function POST(_: Request, context: { params: Promise<{ id: string }> }) {
  const { user, response } = await requireUser(["ADMIN"]);
  if (!user) return response!;
  try {
    const { id } = await context.params;
    const { data, error } = await createAdminClient().rpc("auto_assign_order", { p_order_id: id, p_actor_user_id: user.id, p_excluded_agent_id: null });
    if (error) throw new Error(error.message);
    return ok({ assignedAgentId: data ?? null, assigned: Boolean(data) });
  } catch (error) { return fail("AUTO_ASSIGN_FAILED", error instanceof Error ? error.message : "Unable to auto-assign this order.", 422); }
}
