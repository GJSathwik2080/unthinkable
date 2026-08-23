import { PortalWorkspace } from "@/components/portal-workspace";
export default async function AdminOrderDetail({ params }: { params: Promise<{ id: string }> }) { const { id } = await params; return <PortalWorkspace role="ADMIN" page="order-detail" orderId={id} />; }
