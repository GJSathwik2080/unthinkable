import { redirect } from "next/navigation";
import { getCurrentUser } from "@/lib/auth/require-user";
import { loginPathForRole } from "@/lib/auth/roles";
import type { UserRole } from "@/lib/types";

export async function requirePageRole(role: UserRole) {
  const user = await getCurrentUser();
  if (!user) redirect(loginPathForRole(role, "sign-in"));
  if (user.role !== role) redirect(loginPathForRole(role, "switch-account"));
}
