export interface AgentCandidate { id: string; homeZoneId: string; availability: "AVAILABLE" | "BUSY" | "OFFLINE"; latitude?: number; longitude?: number; locationUpdatedAt?: string; lastAssignedAt: string; }
export interface AssignmentInput { pickupZoneId: string; latitude?: number; longitude?: number; now?: Date; }

export function haversineKm(aLat: number, aLng: number, bLat: number, bLng: number) {
  const r = 6371; const rad = (value: number) => value * Math.PI / 180;
  const dLat = rad(bLat - aLat); const dLng = rad(bLng - aLng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(aLat)) * Math.cos(rad(bLat)) * Math.sin(dLng / 2) ** 2;
  return 2 * r * Math.asin(Math.sqrt(h));
}

export function rankAgents(candidates: AgentCandidate[], input: AssignmentInput) {
  const freshAfter = (input.now ?? new Date()).getTime() - 15 * 60 * 1000;
  return candidates.filter((agent) => agent.availability === "AVAILABLE").map((agent) => {
    const fresh = agent.locationUpdatedAt && new Date(agent.locationUpdatedAt).getTime() >= freshAfter;
    const distance = fresh && input.latitude !== undefined && input.longitude !== undefined && agent.latitude !== undefined && agent.longitude !== undefined
      ? haversineKm(agent.latitude, agent.longitude, input.latitude, input.longitude) : Number.MAX_SAFE_INTEGER;
    return { agent, sameZone: agent.homeZoneId === input.pickupZoneId, fresh: Boolean(fresh), distance };
  }).sort((a, b) => Number(b.sameZone) - Number(a.sameZone) || Number(b.fresh) - Number(a.fresh) || a.distance - b.distance || new Date(a.agent.lastAssignedAt).getTime() - new Date(b.agent.lastAssignedAt).getTime());
}
