import { PortalWorkspace } from "@/components/portal-workspace";
export default async function AgentOrderDetail({ params }: { params: Promise<{ id: string }> }) { const { id } = await params; return <PortalWorkspace role="DELIVERY_AGENT" page="order-detail" orderId={id} />; }
