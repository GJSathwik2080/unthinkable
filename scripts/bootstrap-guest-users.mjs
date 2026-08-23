import { createClient } from "@supabase/supabase-js";

const required = [
  "NEXT_PUBLIC_SUPABASE_URL",
  "SUPABASE_SECRET_KEY",
  "GUEST_CUSTOMER_EMAIL",
  "GUEST_CUSTOMER_PASSWORD",
  "GUEST_ADMIN_EMAIL",
  "GUEST_ADMIN_PASSWORD",
  "GUEST_AGENT_EMAIL",
  "GUEST_AGENT_PASSWORD",
];

const missing = required.filter((name) => !process.env[name]);
if (missing.length) {
  console.error(`Guest bootstrap is not configured. Missing: ${missing.join(", ")}`);
  process.exit(1);
}

const supabase = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL, process.env.SUPABASE_SECRET_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const guests = [
  { role: "CUSTOMER", email: process.env.GUEST_CUSTOMER_EMAIL, password: process.env.GUEST_CUSTOMER_PASSWORD, fullName: "Guest Customer" },
  { role: "ADMIN", email: process.env.GUEST_ADMIN_EMAIL, password: process.env.GUEST_ADMIN_PASSWORD, fullName: "Guest Operations" },
  { role: "DELIVERY_AGENT", email: process.env.GUEST_AGENT_EMAIL, password: process.env.GUEST_AGENT_PASSWORD, fullName: "Guest Delivery Agent" },
];

function describeAuthWriteFailure(role, error) {
  const detail = error?.message ?? "unknown error";
  if (detail === "Internal Server Error") {
    return `Could not prepare ${role} guest because Supabase Auth rejected account creation. Apply supabase/migrations/20260823000600_app_managed_auth_profiles.sql in the Supabase SQL Editor, then retry.`;
  }
  return `Could not prepare ${role} guest: ${detail}`;
}

async function findUser(email) {
  let page = 1;
  while (true) {
    const { data, error } = await supabase.auth.admin.listUsers({ page, perPage: 1000 });
    if (error) throw new Error(`Cannot reach Supabase Auth: ${error.message}`);
    const user = data.users.find((candidate) => candidate.email?.toLowerCase() === email.toLowerCase());
    if (user) return user;
    if (data.users.length < 1000) return null;
    page += 1;
  }
}

async function ensureUser(guest) {
  const existing = await findUser(guest.email);
  if (existing) {
    const { data, error } = await supabase.auth.admin.updateUserById(existing.id, {
      password: guest.password,
      email_confirm: true,
      user_metadata: { full_name: guest.fullName },
    });
    if (error || !data.user) throw new Error(describeAuthWriteFailure(guest.role, error));
    return data.user;
  }
  const { data, error } = await supabase.auth.admin.createUser({
    email: guest.email,
    password: guest.password,
    email_confirm: true,
    user_metadata: { full_name: guest.fullName },
  });
  if (error || !data.user) throw new Error(describeAuthWriteFailure(guest.role, error));
  return data.user;
}

async function main() {
  const prepared = [];
  for (const guest of guests) {
    const user = await ensureUser(guest);
    const { error } = await supabase.from("profiles").upsert({
      id: user.id,
      full_name: guest.fullName,
      role: guest.role,
      is_active: true,
      guest_expires_at: null,
    });
    if (error) throw new Error(`Could not prepare ${guest.role} profile: ${error.message}`);
    prepared.push({ guest, user });
  }

  const agent = prepared.find(({ guest }) => guest.role === "DELIVERY_AGENT");
  const { data: zone, error: zoneError } = await supabase.from("zones").select("id").eq("code", "UNIV").eq("is_active", true).maybeSingle();
  if (zoneError || !zone) throw new Error("Universal service zone is missing. Apply the seed migration before bootstrapping guest accounts.");
  const { error: agentError } = await supabase.from("agent_profiles").upsert({
    user_id: agent.user.id,
    home_zone_id: zone.id,
    availability: "AVAILABLE",
  });
  if (agentError) throw new Error(`Could not prepare delivery-agent profile: ${agentError.message}`);

  for (const { guest } of prepared) console.log(`Prepared fixed ${guest.role} guest account.`);
  console.log("Guest accounts are ready. Run npm run verify:auth to confirm readiness.");
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : "Guest bootstrap failed.");
  process.exit(1);
});
