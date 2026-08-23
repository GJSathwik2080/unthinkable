"use client";

import Link from "next/link";
import { FormEvent, useState } from "react";
import { useSearchParams } from "next/navigation";
import { roleDashboardPaths, roleDescriptions, roleLabels } from "@/lib/auth/roles";
import type { UserRole } from "@/lib/types";

export function RoleLoginForm({ role }: { role: UserRole }) {
  const searchParams = useSearchParams();
  const [error, setError] = useState("");
  const [loading, setLoading] = useState<"credentials" | "guest" | null>(null);
  const reason = searchParams.get("reason");

  async function authenticate(path: string, body: Record<string, string>, mode: "credentials" | "guest") {
    setLoading(mode); setError("");
    try {
      const response = await fetch(path, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
      const payload = await response.json();
      if (!response.ok) throw new Error(payload.error?.message ?? "Unable to sign in.");
      window.location.assign(roleDashboardPaths[role]);
    } catch (cause) { setError(cause instanceof Error ? cause.message : "Unable to sign in."); setLoading(null); }
  }

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    void authenticate("/api/auth/login", { email: String(form.get("email") ?? ""), password: String(form.get("password") ?? ""), role }, "credentials");
  }

  return <main className="auth-page"><section className="auth-card"><Link href="/login" className="side-brand"><span>LM</span><strong>LastMile</strong></Link><p className="section-kicker">{roleLabels[role]}</p><h1>Sign in to {roleLabels[role]}</h1><p className="muted-copy">{roleDescriptions[role]}</p>{reason === "switch-account" && <p className="form-error">This page belongs to a different role. Use the matching account.</p>}
    <form className="form-stack" onSubmit={submit}><label>Email<input name="email" type="email" required autoComplete="email" /></label><label>Password<input name="password" type="password" required autoComplete="current-password" /></label>{error && <p className="form-error">{error}</p>}<button className="button primary wide" disabled={loading !== null}>{loading === "credentials" ? "Signing in…" : `Sign in as ${roleLabels[role]}`}</button></form>
    <div className="auth-foot"><span>Demo access</span><button className="button secondary wide" type="button" disabled={loading !== null} onClick={() => void authenticate("/api/auth/guest", { role }, "guest")}>{loading === "guest" ? "Opening guest workspace…" : `Continue as guest ${roleLabels[role]}`}</button></div>
    {role === "CUSTOMER" && <p className="auth-foot">New customer? <Link href="/register">Create an account</Link></p>}
  </section></main>;
}
