import { fail, ok } from "@/lib/api-response";
import { requireUser } from "@/lib/auth/require-user";
import { listCodSettings } from "@/lib/services/portal-read-service";

export async function GET() {
  const { user, response } = await requireUser(["ADMIN"]);
  if (!user) return response!;
  try { return ok(await listCodSettings()); }
  catch (error) { return fail("COD_SETTINGS_UNAVAILABLE", error instanceof Error ? error.message : "Unable to load COD settings.", 500); }
}
