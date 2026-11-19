"use client";

import { useEffect, useState } from "react";

type Role = "ADMIN" | "OPERATOR" | "VIEWER";

const roleCopy: Record<Role, { title: string; scope: string; permissions: string; restrictions: string }> = {
  ADMIN: {
    title: "Administrator",
    scope: "Global platform scope",
    permissions: "User, branch and settings administration, plus all declared platform capabilities.",
    restrictions: "Destructive Store Commerce force-close still requires explicit per-operation approval and a warning.",
  },
  OPERATOR: {
    title: "Operator",
    scope: "Assigned active branches only",
    permissions: "Create/edit inventory and switch-port/VLAN metadata; run non-destructive discovery and synchronization.",
    restrictions: "No live device configuration, remote sessions, stored credentials, deployments or Store Commerce force-close.",
  },
  VIEWER: {
    title: "Viewer",
    scope: "Assigned active branches only",
    permissions: "Read inventory and switch-port/VLAN metadata.",
    restrictions: "Read-only: no inventory or metadata changes and no operational actions.",
  },
};

export function RoleAccessSummary() {
  const [role, setRole] = useState<Role | null>(null);
  const [unavailable, setUnavailable] = useState(false);

  useEffect(() => {
    let active = true;
    void fetch("/api/v1/session", {
      credentials: "same-origin",
      cache: "no-store",
    })
      .then(async (response) => {
        if (!response.ok) throw new Error("Session unavailable");
        const payload: { user?: { role?: Role } } = await response.json();
        if (!payload.user?.role || !["ADMIN", "OPERATOR", "VIEWER"].includes(payload.user.role)) {
          throw new Error("Role unavailable");
        }
        if (active) setRole(payload.user.role);
      })
      .catch(() => {
        if (active) setUnavailable(true);
      });
    return () => {
      active = false;
    };
  }, []);

  if (!role) {
    return (
      <section
        aria-live="polite"
        className="rounded-xl border border-slate-700/60 bg-slate-900/40 px-4 py-3 text-xs text-slate-400"
      >
        {unavailable ? "Access profile unavailable. Refresh the page to retry." : "Loading your access profile…"}
      </section>
    );
  }

  const policy = roleCopy[role];
  return (
    <section
      aria-label="Your access profile"
      className="rounded-xl border border-slate-700/60 bg-slate-900/40 p-4 sm:p-5"
    >
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <p className="text-[10px] font-semibold uppercase tracking-[.16em] text-slate-500">Your access profile</p>
          <h2 className="mt-1 text-sm font-semibold text-slate-100">{policy.title}</h2>
        </div>
        <span className="rounded-md border border-blue-400/20 bg-blue-400/10 px-2 py-1 text-[10px] font-semibold tracking-wide text-blue-200">
          {policy.scope}
        </span>
      </div>
      <div className="mt-3 grid gap-3 text-xs sm:grid-cols-2">
        <div>
          <p className="font-medium text-emerald-300">Allowed</p>
          <p className="mt-1 leading-5 text-slate-400">{policy.permissions}</p>
        </div>
        <div>
          <p className="font-medium text-amber-300">Restricted</p>
          <p className="mt-1 leading-5 text-slate-400">{policy.restrictions}</p>
        </div>
      </div>
      <p className="mt-3 border-t border-slate-700/50 pt-3 text-[10px] leading-4 text-slate-500">
        These are your approved role permissions. Modules that are not implemented remain unavailable.
      </p>
    </section>
  );
}
