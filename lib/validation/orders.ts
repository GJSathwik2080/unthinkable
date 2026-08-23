import { z } from "zod";

export const quoteSchema = z.object({
  pickupPostalCode: z.string().trim().min(1, "Enter a pickup postal code."),
  dropPostalCode: z.string().trim().min(1, "Enter a drop postal code."),
  lengthCm: z.coerce.number().positive().max(500),
  breadthCm: z.coerce.number().positive().max(500),
  heightCm: z.coerce.number().positive().max(500),
  actualWeightKg: z.coerce.number().positive().max(1000),
  orderType: z.enum(["B2B", "B2C"]),
  paymentType: z.enum(["PREPAID", "COD"]),
});

export const statusChangeSchema = z.object({
  status: z.enum(["PICKED_UP", "IN_TRANSIT", "OUT_FOR_DELIVERY", "DELIVERED", "FAILED"]),
  note: z.string().trim().max(500).optional(),
  failureReason: z.string().trim().min(3).max(500).optional(),
});
