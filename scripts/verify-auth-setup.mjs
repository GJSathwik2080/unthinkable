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
  console.log("Auth configuration: incomplete");
  console.log(`Missing variables: ${missing.join(", ")}`);
  process.exit(1);
}

const supabase = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL, process.env.SUPABASE_SECRET_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});
const expected = [
  { role: "CUSTOMER", email: process.env.GUEST_CUSTOMER_EMAIL },
  { role: "ADMIN", email: process.env.GUEST_ADMIN_EMAIL },
  { role: "DELIVERY_AGENT", email: process.env.GUEST_AGENT_EMAIL },
];

async function listAllUsers() {
  const users = [];
  let page = 1;
  while (true) {
    const { data, error } = await supabase.auth.admin.listUsers({ page, perPage: 1000 });
    if (error) throw new Error("Supabase Auth is unreachable.");
    users.push(...data.users);
    if (data.users.length < 1000) return users;
    page += 1;
  }
}

async function main() {
  const users = await listAllUsers();
  console.log("Supabase Auth: reachable");
  const resolved = expected.map((guest) => ({ ...guest, user: users.find((candidate) => candidate.email?.toLowerCase() === guest.email.toLowerCase()) }));
  const ids = resolved.flatMap(({ user }) => user ? [user.id] : []);
  const { data: profiles, error: profilesError } = ids.length
    ? await supabase.from("profiles").select("id, role, is_active").in("id", ids)
    : { data: [], error: null };
  if (profilesError) throw new Error("Guest profiles cannot be read.");
  const profileById = new Map((profiles ?? []).map((profile) => [profile.id, profile]));

  let ready = true;
  for (const guest of resolved) {
    const profile = guest.user ? profileById.get(guest.user.id) : null;
    const status = profile?.is_active && profile.role === guest.role ? "ready" : "missing or incorrect";
    console.log(`${guest.role} guest: ${status}`);
    if (status !== "ready") ready = false;
  }

  const agent = resolved.find(({ role }) => role === "DELIVERY_AGENT");
  if (agent?.user) {
    const { data: agentProfile, error } = await supabase.from("agent_profiles").select("user_id, availability").eq("user_id", agent.user.id).maybeSingle();
    if (error) throw new Error("Delivery-agent profile cannot be read.");
    const agentReady = Boolean(agentProfile);
    console.log(`Delivery-agent profile: ${agentReady ? `ready (${agentProfile.availability.toLowerCase()})` : "missing"}`);
    if (!agentReady) ready = false;
  } else {
    console.log("Delivery-agent profile: missing");
    ready = false;
  }

  if (!ready) process.exitCode = 1;
}

main().catch((error) => {
  console.log(error instanceof Error ? error.message : "Auth verification failed.");
  process.exit(1);
});
