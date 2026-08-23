export async function sendSms({ to, text }: { to: string; text: string }) {
  const accountSid = process.env.TWILIO_ACCOUNT_SID;
  const token = process.env.TWILIO_AUTH_TOKEN;
  const from = process.env.TWILIO_FROM;
  if (!accountSid || !token || !from) throw new Error("SMS provider is not configured.");
  const body = new URLSearchParams({ To: to, From: from, Body: text });
  const credentials = Buffer.from(`${accountSid}:${token}`).toString("base64");
  const response = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${accountSid}/Messages.json`, { method: "POST", headers: { Authorization: `Basic ${credentials}`, "Content-Type": "application/x-www-form-urlencoded" }, body });
  if (!response.ok) throw new Error(`SMS provider rejected the message (${response.status}).`);
  return response.json() as Promise<{ sid: string }>;
}
