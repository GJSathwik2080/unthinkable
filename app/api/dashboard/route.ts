import { fail, ok } from "@/lib/api-response";
import { requireUser } from "@/lib/auth/require-user";
import { getDashboardForUser } from "@/lib/services/portal-read-service";

export async function GET() {
  const { user, response } = await requireUser();
  if (!user) return response!;
  try { return ok(await getDashboardForUser(user)); }
  catch (error) { return fail("DASHBOARD_UNAVAILABLE", error instanceof Error ? error.message : "Unable to load the dashboard.", 500); }
}
