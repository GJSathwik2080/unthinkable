import { z } from "zod";
import { NextRequest, NextResponse } from "next/server";
import { fail } from "@/lib/api-response";
import { isUserRole } from "@/lib/auth/roles";
import { signInForRole } from "@/lib/auth/sign-in";

const schema = z.object({ email: z.email(), password: z.string().min(1), role: z.string().refine(isUserRole, "Choose a workspace.") });

export async function POST(request: NextRequest) {
  const payload = schema.safeParse(await request.json());
  if (!payload.success) return fail("INVALID_INPUT", "Enter your email and password.", 422, payload.error.flatten().fieldErrors);
  const response = NextResponse.json({ success: true, data: { message: "Signed in." } });
  try {
    await signInForRole(request, response, payload.data, payload.data.role);
    return response;
  } catch (error) { return fail("LOGIN_FAILED", error instanceof Error ? error.message : "Unable to sign in.", 401); }
}
