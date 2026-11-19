import type { ReactNode } from "react";
import {
  Activity,
  Bell,
  Camera,
  ChevronDown,
  CircleHelp,
  Command,
  Database,
  LayoutDashboard,
  Menu,
  Monitor,
  Network,
  Router,
  Search,
  Server,
  Settings,
  ShieldCheck,
  Workflow,
} from "lucide-react";

const navigation = [
  { label: "Overview", icon: LayoutDashboard, active: true },
  { label: "Branches", icon: Network },
  { label: "Device inventory", icon: Monitor },
  { label: "Network devices", icon: Router },
  { label: "Servers & services", icon: Server },
  { label: "CCTV", icon: Camera },
];

const operations = [
  { label: "Monitoring", icon: Activity },
  { label: "Agent management", icon: Workflow },
  { label: "Deployment jobs", icon: Database },
  { label: "Security & access", icon: ShieldCheck },
];

function SectionLabel({ children }: { children: ReactNode }) {
  return (
    <p className="px-3 pb-2 pt-6 text-[10px] font-semibold uppercase tracking-[.18em] text-slate-500">
      {children}
    </p>
  );
}

export default function DashboardPage() {
  return (
    <main className="min-h-screen lg:grid lg:grid-cols-[248px_minmax(0,1fr)]">
      <aside className="hidden border-r border-slate-700/40 bg-slate-950/35 px-4 py-5 lg:flex lg:flex-col">
        <div className="flex items-center gap-3 px-2">
          <div className="grid h-10 w-10 place-items-center rounded-xl border border-blue-400/20 bg-blue-500/15 text-blue-300">
            <Command size={20} />
          </div>
          <div>
            <p className="text-sm font-semibold tracking-tight text-white">Infrastructure</p>
            <p className="mt-0.5 text-[11px] text-slate-500">CONTROL CENTER</p>
          </div>
        </div>

        <nav aria-label="Main navigation" className="mt-8">
          <SectionLabel>Workspace</SectionLabel>
          {navigation.map(({ label, icon: Icon, active }) => (
            active ? (
              <a key={label} href="/" className="sidebar-link" aria-current="page">
                <Icon size={17} strokeWidth={1.8} />
                <span>{label}</span>
              </a>
            ) : (
              <div
                key={label}
                className="sidebar-link is-disabled"
                aria-disabled="true"
                title="This module has not been implemented yet"
              >
                <Icon size={17} strokeWidth={1.8} />
                <span>{label}</span>
                <span className="ml-auto text-[9px] uppercase tracking-wider text-slate-600">Planned</span>
              </div>
            )
          ))}

          <SectionLabel>Operations</SectionLabel>
          {operations.map(({ label, icon: Icon }) => (
            <div
              key={label}
              className="sidebar-link is-disabled"
              aria-disabled="true"
              title="This module has not been implemented yet"
            >
              <Icon size={17} strokeWidth={1.8} />
              <span>{label}</span>
            </div>
          ))}
        </nav>

        <div className="mt-auto rounded-xl border border-slate-700/50 bg-slate-900/70 p-3">
          <div className="flex items-center gap-2 text-xs font-medium text-slate-300">
            <ShieldCheck size={15} className="text-emerald-400" />
            Local development
          </div>
          <p className="mt-2 text-[11px] leading-5 text-slate-500">
            Production services and authentication are not configured yet.
          </p>
        </div>
      </aside>

      <section className="min-w-0">
        <header className="flex h-[72px] items-center justify-between border-b border-slate-700/40 px-5 sm:px-8">
          <div className="flex items-center gap-3">
            <div className="grid h-9 w-9 place-items-center rounded-lg border border-slate-700/60 bg-slate-900 lg:hidden">
              <Command size={18} />
            </div>
            <div>
              <p className="text-xs text-slate-500">Workspace / Overview</p>
              <h1 className="mt-0.5 text-sm font-semibold text-slate-100">Infrastructure overview</h1>
            </div>
          </div>
          <div className="flex items-center gap-2 sm:gap-4">
            <div className="hidden h-9 w-52 items-center gap-2 rounded-lg border border-slate-700/60 bg-slate-900/60 px-3 md:flex">
              <Search size={14} className="text-slate-500" />
              <span className="text-xs text-slate-500">Search (coming soon)</span>
              <kbd className="ml-auto rounded border border-slate-700 px-1.5 py-0.5 text-[10px] text-slate-500">⌘ K</kbd>
            </div>
            <button type="button" aria-label="Notifications (not configured)" disabled className="relative rounded-lg p-2 text-slate-500 opacity-60">
              <Bell size={18} />
            </button>
            <div className="hidden h-8 w-px bg-slate-700/60 sm:block" />
            <button type="button" disabled className="flex items-center gap-2 text-left opacity-70" aria-label="User profile (authentication not configured)">
              <div className="grid h-8 w-8 place-items-center rounded-full bg-slate-700 text-xs font-semibold text-slate-200">IT</div>
              <span className="hidden text-xs text-slate-400 sm:block">Local workspace</span>
              <ChevronDown size={14} className="hidden text-slate-500 sm:block" />
            </button>
          </div>
        </header>

        <div className="mx-auto max-w-[1500px] px-5 py-8 sm:px-8 sm:py-10">
          <div className="flex flex-col justify-between gap-4 sm:flex-row sm:items-end">
            <div>
              <div className="mb-3 inline-flex items-center gap-2 rounded-full border border-blue-400/20 bg-blue-400/10 px-3 py-1 text-[11px] font-medium text-blue-200">
                <span className="h-1.5 w-1.5 rounded-full bg-blue-400" />
                Platform foundation
              </div>
              <h2 className="text-2xl font-semibold tracking-tight text-white sm:text-3xl">Good morning.</h2>
              <p className="mt-2 max-w-2xl text-sm leading-6 text-slate-400">
                A centralized view of your branches, infrastructure and operational services.
              </p>
            </div>
            <div className="flex items-center gap-2 rounded-lg border border-slate-700/50 bg-slate-900/50 px-3 py-2 text-xs text-slate-400">
              <Settings size={14} />
              Initial setup in progress
            </div>
          </div>

          <div className="mt-8 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            {[
              { label: "Branches", value: "—", note: "No branch records yet", icon: Network },
              { label: "Managed devices", value: "—", note: "Inventory not connected", icon: Monitor },
              { label: "Online agents", value: "—", note: "Agent service not deployed", icon: Activity },
              { label: "Active alerts", value: "—", note: "Monitoring not configured", icon: Bell },
            ].map(({ label, value, note, icon: Icon }) => (
              <article key={label} className="panel rounded-2xl p-5">
                <div className="flex items-center justify-between">
                  <p className="text-xs font-medium text-slate-400">{label}</p>
                  <span className="stat-icon"><Icon size={17} /></span>
                </div>
                <p className="mt-5 text-3xl font-semibold tracking-tight text-slate-100">{value}</p>
                <p className="mt-1.5 text-[11px] text-slate-500">{note}</p>
              </article>
            ))}
          </div>

          <div className="mt-6 grid gap-5 xl:grid-cols-[minmax(0,1.5fr)_minmax(300px,1fr)]">
            <section className="panel rounded-2xl p-5 sm:p-6">
              <div className="flex items-center justify-between">
                <div>
                  <h3 className="text-sm font-semibold text-slate-100">Infrastructure status</h3>
                  <p className="mt-1 text-xs text-slate-500">Service connectivity will appear here when configured.</p>
                </div>
                <span className="rounded-md border border-slate-700/60 px-2 py-1 text-[10px] text-slate-500">NO DATA</span>
              </div>
              <div className="mt-6 flex min-h-48 flex-col items-center justify-center rounded-xl border border-dashed border-slate-700/70 bg-slate-950/20 px-5 text-center">
                <div className="grid h-11 w-11 place-items-center rounded-xl border border-slate-700/60 bg-slate-900 text-slate-400">
                  <Activity size={20} />
                </div>
                <p className="mt-4 text-sm font-medium text-slate-300">No infrastructure data available</p>
                <p className="mt-1.5 max-w-sm text-xs leading-5 text-slate-500">
                  Branches, devices and monitoring history will be shown after their respective modules are implemented and configured.
                </p>
              </div>
            </section>

            <section className="panel rounded-2xl p-5 sm:p-6">
              <div className="flex items-center justify-between">
                <h3 className="text-sm font-semibold text-slate-100">Platform components</h3>
                <CircleHelp size={16} className="text-slate-500" />
              </div>
              <div className="mt-5 space-y-4">
                {[
                  { label: "Web interface", detail: "Next.js application", state: "Scaffolded", color: "text-emerald-300" },
                  { label: "API service", detail: "Authentication and domain API", state: "Planned", color: "text-slate-400" },
                  { label: "Background worker", detail: "Durable jobs and monitoring", state: "Planned", color: "text-slate-400" },
                  { label: "PostgreSQL", detail: "Dedicated database service", state: "Planned", color: "text-slate-400" },
                  { label: "TLS edge", detail: "HTTPS and WSS entry point", state: "Planned", color: "text-slate-400" },
                ].map((item, index) => (
                  <div key={item.label} className="flex items-center gap-3">
                    <div className="grid h-8 w-8 shrink-0 place-items-center rounded-lg bg-slate-900 text-slate-400">
                      {index === 0 ? <Monitor size={15} /> : index === 1 ? <Workflow size={15} /> : index === 2 ? <Activity size={15} /> : index === 3 ? <Database size={15} /> : <Server size={15} />}
                    </div>
                    <div className="min-w-0 flex-1">
                      <p className="text-xs font-medium text-slate-300">{item.label}</p>
                      <p className="mt-0.5 text-[10px] text-slate-500">{item.detail}</p>
                    </div>
                    <span className={`text-[10px] font-medium ${item.color}`}>{item.state}</span>
                  </div>
                ))}
              </div>
              <div className="mt-6 flex items-center gap-2 border-t border-slate-700/50 pt-4 text-[10px] text-slate-500">
                <ShieldCheck size={13} />
                Status reflects implementation, not simulated health.
              </div>
            </section>
          </div>

          <footer className="mt-8 flex flex-col gap-2 border-t border-slate-700/40 pt-5 text-[10px] text-slate-600 sm:flex-row sm:items-center sm:justify-between">
            <span>Infrastructure Control Center · Bootstrap 0.1.0</span>
            <span>Development environment · No production connection</span>
          </footer>
        </div>
      </section>
    </main>
  );
}
