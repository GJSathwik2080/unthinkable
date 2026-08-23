import Link from "next/link";
import { roleDescriptions, roleLabels, roleLoginPaths, userRoles } from "@/lib/auth/roles";

export default function LoginPage() {
  return <main className="auth-page"><section className="auth-card role-chooser"><Link href="/" className="side-brand"><span>LM</span><strong>LastMile</strong></Link><p className="section-kicker">Choose your workspace</p><h1>Sign in to LastMile</h1><p className="muted-copy">Select the portal that matches your role.</p><div className="role-cards">{userRoles.map((role) => <Link href={roleLoginPaths[role]} className="role-card-link" key={role}><strong>{roleLabels[role]}</strong><span>{roleDescriptions[role]}</span><em>Open sign in →</em></Link>)}</div></section></main>;
}
