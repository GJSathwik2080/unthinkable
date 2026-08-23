import { z } from "zod";

const requiredText = z.string().trim().min(1, "Required.");
const phoneNumber = z.string()
  .transform((value) => {
    const digits = value.replace(/\D/g, "");
    return digits.length === 12 && digits.startsWith("91") ? digits.slice(2) : digits;
  })
  .pipe(z.string().regex(/^\d{10}$/, "Phone number must contain 10 digits."));

const addressSchema = z.object({
  recipientName: requiredText,
  phone: phoneNumber,
  addressLine1: requiredText,
  addressLine2: z.string().trim().optional(),
  postalCode: requiredText,
});

export const createOrderSchema = z.object({
  customerId: z.uuid().optional(),
  pickup: addressSchema,
  drop: addressSchema,
  lengthCm: z.coerce.number().positive().max(500),
  breadthCm: z.coerce.number().positive().max(500),
  heightCm: z.coerce.number().positive().max(500),
  actualWeightKg: z.coerce.number().positive().max(1000),
  orderType: z.enum(["B2B", "B2C"]),
  paymentType: z.enum(["PREPAID", "COD"]),
  scheduledDeliveryDate: z.iso.date().optional(),
});

export const rescheduleSchema = z.object({ scheduledDeliveryDate: z.iso.date() });
export const agentAvailabilitySchema = z.object({ availability: z.enum(["AVAILABLE", "BUSY", "OFFLINE"]) });
export const agentLocationSchema = z.object({ latitude: z.coerce.number().min(-90).max(90), longitude: z.coerce.number().min(-180).max(180) });
