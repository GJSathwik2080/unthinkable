import { NextRequest, NextResponse } from "next/server";
import { fail } from "@/lib/api-response";
import { createRouteClient } from "@/lib/supabase/route";

export async function POST(request: NextRequest) {
  const response = NextResponse.json({ success: true, data: { message: "Signed out." } });
  try { const { error } = await createRouteClient(request, response).auth.signOut(); if (error) throw error; return response; }
  catch (error) { return fail("LOGOUT_FAILED", error instanceof Error ? error.message : "Unable to sign out.", 500); }
}
