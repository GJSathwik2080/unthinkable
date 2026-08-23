import { describe, expect, it } from "vitest";
import { rankAgents } from "../lib/domain/assignment";

describe("agent assignment", () => {
  it("prefers a nearby available agent in the pickup zone", () => {
    const ranked = rankAgents([
      { id: "outside", homeZoneId: "zone-b", availability: "AVAILABLE", latitude: 13.08, longitude: 80.28, locationUpdatedAt: "2026-08-21T09:55:00Z", lastAssignedAt: "2026-08-20T10:00:00Z" },
      { id: "nearby", homeZoneId: "zone-a", availability: "AVAILABLE", latitude: 13.088, longitude: 80.289, locationUpdatedAt: "2026-08-21T09:57:00Z", lastAssignedAt: "2026-08-20T12:00:00Z" },
      { id: "busy", homeZoneId: "zone-a", availability: "BUSY", lastAssignedAt: "2026-08-20T10:00:00Z" },
    ], { pickupZoneId: "zone-a", latitude: 13.0878, longitude: 80.2882, now: new Date("2026-08-21T10:00:00Z") });
    expect(ranked.map((entry) => entry.agent.id)).toEqual(["nearby", "outside"]);
  });
});
