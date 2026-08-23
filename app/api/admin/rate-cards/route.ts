import { fail, ok } from "@/lib/api-response";
import { requireUser } from "@/lib/auth/require-user";
import { listRateCards } from "@/lib/services/portal-read-service";

export async function GET() {
  const { user, response } = await requireUser(["ADMIN"]);
  if (!user) return response!;
  try { return ok(await listRateCards()); }
  catch (error) { return fail("RATE_CARDS_UNAVAILABLE", error instanceof Error ? error.message : "Unable to load rate cards.", 500); }
}
