import { areGuestCredentialsConfigured, getGuestCredentials, isGuestLoginEnabled } from "@/lib/auth/guest";
import { createAdminClient } from "@/lib/supabase/admin";
import type { UserRole } from "@/lib/types";

type GuestReadiness = "disabled" | "unconfigured" | "ready" | "accounts_missing" | "unreachable";

const guestRoles: UserRole[] = ["CUSTOMER", "ADMIN", "DELIVERY_AGENT"];

export async function getGuestLoginReadiness(): Promise<GuestReadiness> {
  if (!isGuestLoginEnabled()) return "disabled";
  if (!areGuestCredentialsConfigured()) return "unconfigured";

  try {
    const admin = createAdminClient();
    const { data: authData, error: authError } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
    if (authError) return "unreachable";
    const users = guestRoles.map((role) => {
      const { email } = getGuestCredentials(role);
      return { role, user: authData.users.find((candidate) => candidate.email?.toLowerCase() === email.toLowerCase()) };
    });
    if (users.some(({ user }) => !user)) return "accounts_missing";
    const ids = users.map(({ user }) => user!.id);
    const { data: profiles, error: profileError } = await admin.from("profiles").select("id, role, is_active").in("id", ids);
    if (profileError) return "unreachable";
    if (users.some(({ role, user }) => {
      const profile = profiles?.find((candidate) => candidate.id === user!.id);
      return profile?.role !== role || !profile.is_active;
    })) return "accounts_missing";
    const agentId = users.find(({ role }) => role === "DELIVERY_AGENT")!.user!.id;
    const { data: agent, error: agentError } = await admin.from("agent_profiles").select("user_id, availability").eq("user_id", agentId).maybeSingle();
    if (agentError) return "unreachable";
    // An assigned guest agent becomes BUSY during normal workflow. That must
    // never disable login for every guest role; only the profile's existence
    // determines whether the guest account is ready.
    return agent?.user_id ? "ready" : "accounts_missing";
  } catch {
    return "unreachable";
  }
}
