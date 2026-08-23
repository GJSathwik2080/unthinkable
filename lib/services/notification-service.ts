import { sendEmail } from "@/lib/notifications/email";
import { sendSms } from "@/lib/notifications/sms";
import { statusNotification } from "@/lib/notifications/templates";
import { createAdminClient } from "@/lib/supabase/admin";
import type { OrderStatus } from "@/lib/types";

type OutboxRow = {
  id: string;
  channel: "EMAIL" | "SMS";
  recipient: string;
  attempt_count: number;
  order_events: { status: OrderStatus; orders: { tracking_number: string } | { tracking_number: string }[] } | null;
};

function trackingNumber(row: OutboxRow) {
  const order = Array.isArray(row.order_events?.orders) ? row.order_events?.orders[0] : row.order_events?.orders;
  return order?.tracking_number ?? "your shipment";
}

export async function processPendingNotifications(limit = 25) {
  const db = createAdminClient();
  const { data, error } = await db
    .from("notification_outbox")
    .select("id, channel, recipient, attempt_count, order_events!inner(status, orders!inner(tracking_number))")
    .in("status", ["PENDING", "FAILED"])
    .lte("next_attempt_at", new Date().toISOString())
    .order("created_at")
    .limit(limit);
  if (error) throw new Error(error.message);

  let processed = 0;
  for (const raw of (data ?? []) as unknown as OutboxRow[]) {
    const { data: claim } = await db
      .from("notification_outbox")
      .update({ status: "PROCESSING", attempt_count: raw.attempt_count + 1, claimed_at: new Date().toISOString() })
      .eq("id", raw.id)
      .in("status", ["PENDING", "FAILED"])
      .select("id")
      .maybeSingle();
    if (!claim) continue;

    try {
      const event = raw.order_events;
      if (!event) throw new Error("Outbox event is missing.");
      const message = statusNotification(trackingNumber(raw), event.status);
      const providerMessageId = raw.channel === "EMAIL"
        ? (await sendEmail({ to: raw.recipient, ...message })).id
        : (await sendSms({ to: raw.recipient, text: message.text })).sid;
      const { error: updateError } = await db
        .from("notification_outbox")
        .update({ status: "SENT", provider_message_id: providerMessageId, sent_at: new Date().toISOString(), last_error: null, claimed_at: null })
        .eq("id", raw.id);
      if (updateError) throw new Error(updateError.message);
      processed += 1;
    } catch (error) {
      const delayMinutes = Math.min(60, 2 ** Math.min(raw.attempt_count, 5));
      await db.from("notification_outbox").update({
        status: "FAILED",
        claimed_at: null,
        last_error: error instanceof Error ? error.message.slice(0, 1000) : "Unknown delivery provider failure.",
        next_attempt_at: new Date(Date.now() + delayMinutes * 60_000).toISOString(),
      }).eq("id", raw.id);
    }
  }
  return { processed, inspected: data?.length ?? 0 };
}
