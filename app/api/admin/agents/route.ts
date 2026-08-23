import { fail, ok } from "@/lib/api-response";
import { requireUser } from "@/lib/auth/require-user";
import { listAdminAgents } from "@/lib/services/portal-read-service";

export async function GET() {
  const { user, response } = await requireUser(["ADMIN"]);
  if (!user) return response!;
  try { return ok(await listAdminAgents()); }
  catch (error) { return fail("AGENTS_UNAVAILABLE", error instanceof Error ? error.message : "Unable to load agents.", 500); }
}
