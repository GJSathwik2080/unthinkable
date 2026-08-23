import { PortalWorkspace } from "@/components/portal-workspace";
export default async function CustomerOrderDetail({ params }: { params: Promise<{ id: string }> }) { const { id } = await params; return <PortalWorkspace role="CUSTOMER" page="order-detail" orderId={id} />; }
