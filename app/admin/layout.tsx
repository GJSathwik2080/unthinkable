import { requirePageRole } from "@/lib/auth/require-page-role";

export default async function AdminLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  await requirePageRole("ADMIN");
  return children;
}
