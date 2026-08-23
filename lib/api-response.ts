import { NextResponse } from "next/server";

export function ok<T>(data: T, init?: ResponseInit) { return NextResponse.json({ success: true, data }, init); }
export function fail(code: string, message: string, status = 400, fieldErrors?: Record<string, string[]>) {
  return NextResponse.json({ success: false, error: { code, message, fieldErrors } }, { status });
}
