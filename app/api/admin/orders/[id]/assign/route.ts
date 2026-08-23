import { z } from "zod";
import { fail, ok } from "@/lib/api-response";
import { requireUser } from "@/lib/auth/require-user";
import { createAdminClient } from "@/lib/supabase/admin";

const assignmentSchema = z.object({ agentId: z.uuid() });

export async function POST(request: Request, context: { params: Promise<{ id: string }> }) {
  const { user, response } = await requireUser(["ADMIN"]);
  if (!user) return response!;
  const payload = assignmentSchema.safeParse(await request.json());
  if (!payload.success) return fail("INVALID_INPUT", "Choose a valid delivery agent.", 422, payload.error.flatten().fieldErrors);
  try {
    const { id } = await context.params;
    const { error } = await createAdminClient().rpc("assign_order_manually", {
      p_order_id: id, p_agent_id: payload.data.agentId, p_actor_user_id: user.id,
    });
    if (error) throw new Error(error.message);
    return ok({ orderId: id, assignedAgentId: payload.data.agentId });
  } catch (error) { return fail("MANUAL_ASSIGN_FAILED", error instanceof Error ? error.message : "Unable to assign this order.", 422); }
}
