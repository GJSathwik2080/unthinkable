import { fail } from "@/lib/api-response";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import type { UserRole } from "@/lib/types";

export interface CurrentUser { id: string; email: string; role: UserRole; fullName: string; }

export async function getCurrentUser(): Promise<CurrentUser | null> {
  if (!process.env.NEXT_PUBLIC_SUPABASE_URL || !process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY || !process.env.SUPABASE_SECRET_KEY) return null;
  const sessionClient = await createClient();
  const { data: { user }, error } = await sessionClient.auth.getUser();
  if (error || !user) return null;
  const admin = createAdminClient();
  const { data: profile } = await admin.from("profiles").select("full_name, role, is_active").eq("id", user.id).maybeSingle();
  if (!profile?.is_active) return null;
  return { id: user.id, email: user.email ?? "", role: profile.role as UserRole, fullName: profile.full_name };
}

export async function requireUser(roles?: UserRole[]) {
  const user = await getCurrentUser();
  if (!user) return { user: null, response: fail("UNAUTHENTICATED", "Please sign in to continue.", 401) };
  if (roles && !roles.includes(user.role)) return { user: null, response: fail("FORBIDDEN", "You do not have permission for this action.", 403) };
  return { user, response: null };
}
