import { z } from "zod";
import { NextRequest, NextResponse } from "next/server";
import { fail } from "@/lib/api-response";
import { getGuestCredentials, GuestConfigurationError, isGuestLoginEnabled } from "@/lib/auth/guest";
import { getGuestLoginReadiness } from "@/lib/auth/guest-readiness";
import { isUserRole } from "@/lib/auth/roles";
import { RoleSignInError, signInForRole } from "@/lib/auth/sign-in";

const schema = z.object({ role: z.string().refine(isUserRole, "Choose a workspace.") });

export async function POST(request: NextRequest) {
  if (!isGuestLoginEnabled()) return fail("GUEST_LOGIN_DISABLED", "Guest login is currently disabled.", 404);
  const payload = schema.safeParse(await request.json());
  if (!payload.success) return fail("INVALID_INPUT", "Choose a workspace.", 422);
  const readiness = await getGuestLoginReadiness();
  if (readiness !== "ready") return fail("GUEST_LOGIN_UNCONFIGURED", "Guest accounts are not ready. Set the guest environment variables and run npm run bootstrap:guests.", 503);
  try {
    const response = NextResponse.json({ success: true, data: { message: "Guest session started." } });
    await signInForRole(request, response, getGuestCredentials(payload.data.role), payload.data.role);
    return response;
  } catch (error) {
    if (error instanceof GuestConfigurationError) return fail("GUEST_LOGIN_UNCONFIGURED", error.message, 503);
    if (error instanceof RoleSignInError && error.kind === "AUTHENTICATION") return fail("GUEST_LOGIN_FAILED", "Guest account credentials are invalid. Run the guest bootstrap script.", 401);
    if (error instanceof RoleSignInError && ["PROFILE", "CONFIGURATION"].includes(error.kind)) return fail("GUEST_LOGIN_UNCONFIGURED", error.message, 503);
    return fail("GUEST_LOGIN_FAILED", "Unable to start the guest session. Check the server logs.", 500);
  }
}
