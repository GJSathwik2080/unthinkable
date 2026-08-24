import { z } from "zod";
import { NextRequest, NextResponse } from "next/server";
import { fail, ok } from "@/lib/api-response";
import { getCurrentUser } from "@/lib/auth/require-user";
import { createRouteClient } from "@/lib/supabase/route";

export async function GET() {
  const user = await getCurrentUser();
  return user ? ok(user) : fail("UNAUTHENTICATED", "Please sign in to continue.", 401);
}

const patchSchema = z.object({ fullName: z.string().trim().min(2).max(120) });

export async function PATCH(request: NextRequest) {
  const user = await getCurrentUser();
  if (!user) return fail("UNAUTHENTICATED", "Please sign in.", 401);

  const payload = patchSchema.safeParse(await request.json());
  if (!payload.success) return fail("INVALID_INPUT", "Enter a valid name.", 422);

  const client = createRouteClient(request, new NextResponse());
  
  const { error: authError } = await client.auth.updateUser({ data: { full_name: payload.data.fullName } });
  if (authError) return fail("UPDATE_FAILED", authError.message, 500);
  
  const { error: profileError } = await client.from("profiles").update({ full_name: payload.data.fullName }).eq("id", user.id);
  if (profileError) return fail("UPDATE_FAILED", profileError.message, 500);

  return ok({ success: true });
}
