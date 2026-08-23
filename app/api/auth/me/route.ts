import { fail, ok } from "@/lib/api-response";
import { getCurrentUser } from "@/lib/auth/require-user";

export async function GET() {
  const user = await getCurrentUser();
  return user ? ok(user) : fail("UNAUTHENTICATED", "Please sign in to continue.", 401);
}
