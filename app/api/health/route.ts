import { ok } from "@/lib/api-response";
import { getGuestLoginReadiness } from "@/lib/auth/guest-readiness";
import { isDatabaseConfigured } from "@/lib/services/order-service";
import { createAdminClient } from "@/lib/supabase/admin";

export async function GET() {
  let database: "unconfigured" | "reachable" | "unreachable" = "unconfigured";
  let auth: "unconfigured" | "reachable" | "unreachable" = "unconfigured";
  if (isDatabaseConfigured()) {
    try {
      const admin = createAdminClient();
      const [{ error: databaseError }, { error: authError }] = await Promise.all([
        admin.from("pricing_settings").select("id", { head: true }).limit(1),
        admin.auth.admin.listUsers({ page: 1, perPage: 1 }),
      ]);
      database = databaseError ? "unreachable" : "reachable";
      auth = authError ? "unreachable" : "reachable";
    } catch {
      database = "unreachable";
      auth = "unreachable";
    }
  }
  const guestLogin = await getGuestLoginReadiness();
  const degraded = database === "unreachable" || auth === "unreachable" || guestLogin === "unreachable";
  return ok({ service: "last-mile-delivery", status: degraded ? "degraded" : "healthy", database, auth, guestLogin, timestamp: new Date().toISOString() });
}
