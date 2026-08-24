import { z } from "zod";
import { NextRequest, NextResponse } from "next/server";
import { fail } from "@/lib/api-response";
import { createAdminClient } from "@/lib/supabase/admin";
import { createRouteClient } from "@/lib/supabase/route";

const schema = z.object({ fullName: z.string().trim().min(2).max(120), phone: z.string().trim().min(8).max(24).optional().or(z.literal("")), email: z.email(), password: z.string().min(8).max(128) });

export async function POST(request: NextRequest) {
  const payload = schema.safeParse(await request.json());
  if (!payload.success) return fail("INVALID_INPUT", "Enter a valid name, email, and password.", 422, payload.error.flatten().fieldErrors);
  const response = NextResponse.json({ success: true, data: { message: "Registration successful." } }, { status: 201 });
  try {
    const client = createRouteClient(request, response);
    const { data, error } = await client.auth.signUp({ email: payload.data.email, password: payload.data.password, options: { data: { full_name: payload.data.fullName, phone: payload.data.phone || null } } });
    if (error || !data.user) return fail("REGISTER_FAILED", error?.message ?? "Unable to create the account.", 422);
    const admin = createAdminClient();
    const { data: authUser, error: authUserError } = await admin.auth.admin.getUserById(data.user.id);
    if (authUserError || !authUser.user) return fail("REGISTER_FAILED", "This email cannot be registered again. Sign in instead, or use a different email.", 409);
    const { error: profileError } = await admin.from("profiles").upsert({ id: authUser.user.id, full_name: payload.data.fullName, phone: payload.data.phone || null, role: "CUSTOMER", is_active: true });
    if (profileError) return fail("REGISTER_FAILED", profileError.message, 500);
    return response;
  } catch (error) { return fail("REGISTER_FAILED", error instanceof Error ? error.message : "Unable to create this account.", 500); }
}
