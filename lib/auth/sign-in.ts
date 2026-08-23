import { createClient } from "@supabase/supabase-js";
import type { NextRequest, NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { createRouteClient } from "@/lib/supabase/route";
import type { UserRole } from "@/lib/types";

export class RoleSignInError extends Error {
  constructor(readonly kind: "AUTHENTICATION" | "PROFILE" | "CONFIGURATION" | "SESSION", message: string) {
    super(message);
  }
}

export async function signInForRole(
  request: NextRequest,
  response: NextResponse,
  credentials: { email: string; password: string },
  expectedRole: UserRole,
) {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const publishableKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  if (!url || !publishableKey) throw new RoleSignInError("CONFIGURATION", "Supabase authentication is not configured.");

  const auth = createClient(url, publishableKey, { auth: { autoRefreshToken: false, persistSession: false } });
  const { data, error } = await auth.auth.signInWithPassword(credentials);
  if (error || !data.session || !data.user) throw new RoleSignInError("AUTHENTICATION", error?.message ?? "Unable to sign in.");

  const { data: profile, error: profileError } = await createAdminClient()
    .from("profiles")
    .select("role, is_active")
    .eq("id", data.user.id)
    .maybeSingle();
  if (profileError || !profile?.is_active) throw new RoleSignInError("PROFILE", "This account is inactive or its profile is not ready.");
  if (profile.role !== expectedRole) throw new RoleSignInError("PROFILE", "This account belongs to a different workspace. Choose the matching login.");

  const routeClient = createRouteClient(request, response);
  const { error: sessionError } = await routeClient.auth.setSession({
    access_token: data.session.access_token,
    refresh_token: data.session.refresh_token,
  });
  if (sessionError) throw new RoleSignInError("SESSION", sessionError.message);
  return { id: data.user.id, role: profile.role as UserRole };
}
