"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { LogOut } from "lucide-react";

export function LogoutButton() {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function signOut() {
    setBusy(true);
    setError("");

    try {
      const response = await fetch("/api/v1/auth/logout", {
        method: "POST",
        credentials: "same-origin",
        cache: "no-store",
      });

      if (!response.ok && response.status !== 204) {
        throw new Error("The API rejected the sign-out request.");
      }

      router.replace("/login");
      router.refresh();
    } catch {
      setError("Unable to sign out. Check the API connection and try again.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="flex flex-col items-end gap-1">
      <button
        type="button"
        onClick={signOut}
        disabled={busy}
        className="inline-flex items-center gap-2 rounded-lg border border-slate-700/60 bg-slate-900/60 px-3 py-2 text-xs text-slate-300 transition hover:border-slate-600 hover:bg-slate-800 disabled:cursor-wait disabled:opacity-50"
        aria-label="Sign out"
      >
        <LogOut size={15} />
        {busy ? "Signing out…" : "Sign out"}
      </button>
      {error && (
        <span role="alert" className="max-w-52 text-right text-[10px] text-rose-300">
          {error}
        </span>
      )}
    </div>
  );
}
