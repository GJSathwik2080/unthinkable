import { requirePageRole } from "@/lib/auth/require-page-role";

export default async function AgentLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  await requirePageRole("DELIVERY_AGENT");
  return children;
}
