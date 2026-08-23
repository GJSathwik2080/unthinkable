import type { Money } from "@/lib/types";

export function formatMoney(value: Money) {
  return new Intl.NumberFormat("en-IN", { style: "currency", currency: value.currency, maximumFractionDigits: 2 }).format(value.amountMinor / 100);
}

export function formatWeight(grams: number) {
  return grams >= 1000 ? `${(grams / 1000).toFixed(2).replace(/\.00$/, "")} kg` : `${grams} g`;
}
