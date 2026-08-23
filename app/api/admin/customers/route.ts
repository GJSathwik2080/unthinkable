import { fail, ok } from "@/lib/api-response";
import { requireUser } from "@/lib/auth/require-user";
import { listAdminCustomers } from "@/lib/services/portal-read-service";

export async function GET() {
  const { user, response } = await requireUser(["ADMIN"]);
  if (!user) return response!;
  try { return ok(await listAdminCustomers()); }
  catch (error) { return fail("CUSTOMERS_UNAVAILABLE", error instanceof Error ? error.message : "Unable to load customers.", 500); }
}
