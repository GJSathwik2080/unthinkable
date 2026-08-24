"use client";

import Link from "next/link";
import { FormEvent, useState } from "react";

export default function RegisterPage() {
  const [error, setError] = useState(""); const [message, setMessage] = useState(""); const [loading, setLoading] = useState(false);
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); setLoading(true); setError(""); setMessage(""); const form = new FormData(event.currentTarget);
    try { const response = await fetch("/api/auth/register", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ fullName: form.get("fullName"), phone: form.get("phone"), email: form.get("email"), password: form.get("password") }) }); const body = await response.json(); if (!response.ok) throw new Error(body.error?.message ?? "Unable to create this account."); setMessage(body.data.message); }
    catch (reason) { setError(reason instanceof Error ? reason.message : "Unable to create this account."); }
    finally { setLoading(false); }
  }
  return <main className="auth-page"><form className="auth-card" onSubmit={submit}><Link href="/" className="side-brand"><span>LM</span><strong>LastMile</strong></Link><p className="section-kicker">Customer account</p><h1>Create your workspace</h1><label>Full name<input name="fullName" required /></label><label>Phone (Optional)<input name="phone" /></label><label>Email<input name="email" type="email" required autoComplete="email" /></label><label>Password<input name="password" type="password" minLength={8} required autoComplete="new-password" /></label>{error && <p className="form-error">{error}</p>}{message && <p className="success-message">{message}</p>}<button className="button primary wide" disabled={loading}>{loading ? "Creating…" : "Create customer account"}</button><p className="auth-foot">Already have an account? <Link href="/login">Sign in</Link></p></form></main>;
}
