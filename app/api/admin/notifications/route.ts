import { fail, ok } from "@/lib/api-response";
import { requireUser } from "@/lib/auth/require-user";
import { listNotifications } from "@/lib/services/portal-read-service";

export async function GET() {
  const { user, response } = await requireUser(["ADMIN"]);
  if (!user) return response!;
  try { return ok(await listNotifications()); }
  catch (error) { return fail("NOTIFICATIONS_UNAVAILABLE", error instanceof Error ? error.message : "Unable to load notifications.", 500); }
}
