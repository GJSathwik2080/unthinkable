import { fail, ok } from "@/lib/api-response";
import { lookupArea } from "@/lib/services/order-service";

export async function GET(request: Request) {
  const postalCode = new URL(request.url).searchParams.get("postalCode");
  if (!postalCode) return fail("POSTAL_CODE_REQUIRED", "postalCode is required.", 422);
  try { return ok(await lookupArea(postalCode)); }
  catch (error) { return fail("AREA_UNSUPPORTED", error instanceof Error ? error.message : "Area is unsupported.", 404); }
}
