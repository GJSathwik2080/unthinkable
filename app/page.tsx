import Link from "next/link";
import { roleLoginPaths } from "@/lib/auth/roles";

export default function Home() {
  return (
    <main className="welcome-page">
      <section className="welcome-card">
        <div className="brand-mark">LM</div>
        <p className="eyebrow">Delivery operations, made visible</p>
        <h1>Every mile. One calm command center.</h1>
        <p className="welcome-copy">A role-based platform for quoting, assigning, tracking, and completing last-mile deliveries.</p>
        <div className="role-launchers">
          <Link className="launcher primary-launcher" href={roleLoginPaths.CUSTOMER}><span>Customer portal</span><small>Quote and track shipments</small></Link>
          <Link className="launcher" href={roleLoginPaths.ADMIN}><span>Operations console</span><small>Manage your delivery network</small></Link>
          <Link className="launcher" href={roleLoginPaths.DELIVERY_AGENT}><span>Agent workspace</span><small>Complete deliveries on the move</small></Link>
        </div>
      </section>
      <aside className="welcome-aside">
        <div className="route-card"><span className="pulse-dot" /><div><strong>Shared order lifecycle</strong><small>One order record, three role-specific workspaces</small></div></div>
        <div className="route-line"><span /><i /><span /></div>
        <p>Quote accurately. Assign confidently. Keep every delivery accountable.</p>
      </aside>
    </main>
  );
}
