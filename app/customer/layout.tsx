import { requirePageRole } from "@/lib/auth/require-page-role";

export default async function CustomerLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  await requirePageRole("CUSTOMER");
  return children;
}
