import { notFound } from "next/navigation";
import { RoleLoginForm } from "@/components/role-login-form";
import { roleFromLoginSlug } from "@/lib/auth/roles";

export default async function RoleLoginPage({ params }: { params: Promise<{ role: string }> }) {
  const { role: slug } = await params;
  const role = roleFromLoginSlug(slug);
  if (!role) notFound();
  return <RoleLoginForm role={role} />;
}
