import { fail, ok } from "@/lib/api-response";
import { processPendingNotifications } from "@/lib/services/notification-service";

/**
 * Vercel invokes this route hourly. Once Supabase credentials are configured,
 * notification-service.ts can claim PENDING outbox rows here and send them via
 * the configured Resend/Twilio HTTP providers. The endpoint is intentionally
 * safe to call repeatedly: rows are keyed by tracking event + channel.
 */
export async function POST(request: Request) {
  const secret = process.env.CRON_SECRET;
  if (!secret || request.headers.get("authorization") !== `Bearer ${secret}`) {
    return fail("UNAUTHORIZED", "Invalid cron authorization.", 401);
  }

  try {
    return ok(await processPendingNotifications());
  } catch (error) {
    return fail("NOTIFICATION_WORKER_FAILED", error instanceof Error ? error.message : "Unable to process notification jobs.", 500);
  }
}
