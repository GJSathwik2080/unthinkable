import { fail, ok } from "@/lib/api-response";
import { requireUser } from "@/lib/auth/require-user";
import { getOrderForUser, getTrackingNumber, listOrdersForUser } from "@/lib/services/order-read-service";
import { createOrder } from "@/lib/services/order-service";
import { createOrderSchema } from "@/lib/validation/order-create";

export const runtime = "nodejs";

export async function GET() {
  const { user, response } = await requireUser();
  if (!user) return response!;
  try {
    return ok(await listOrdersForUser(user));
  } catch (error) {
    return fail("ORDERS_UNAVAILABLE", error instanceof Error ? error.message : "Unable to load orders.", 500);
  }
}

export async function POST(request: Request) {
  const { user, response } = await requireUser(["CUSTOMER", "ADMIN"]);
  if (!user) return response!;

  const payload = createOrderSchema.safeParse(await request.json());
  if (!payload.success) {
    const issue = payload.error.issues[0];
    const field = issue.path.map((part) => String(part).replace(/([A-Z])/g, " $1")).join(" ").replace(/^./, (value) => value.toUpperCase());
    return fail("INVALID_INPUT", `${field}: ${issue.message}`, 422, payload.error.flatten().fieldErrors);
  }
  if (user.role === "CUSTOMER" && payload.data.customerId && payload.data.customerId !== user.id) {
    return fail("FORBIDDEN", "Customers can create orders only for themselves.", 403);
  }
  if (user.role === "ADMIN" && !payload.data.customerId) {
    return fail("CUSTOMER_REQUIRED", "Select the customer who owns this order.", 422);
  }

  try {
    const { customerId, scheduledDeliveryDate, ...order } = payload.data;
    const orderId = await createOrder(customerId ?? user.id, user.id, order, scheduledDeliveryDate);
    const trackingNumber = await getTrackingNumber(orderId);
    const createdOrder = await getOrderForUser(orderId, { ...user, role: "ADMIN" });
    return ok({ id: orderId, trackingNumber, order: createdOrder }, { status: 201 });
  } catch (error) {
    return fail("ORDER_CREATE_FAILED", error instanceof Error ? error.message : "Unable to create this order.", 422);
  }
}
