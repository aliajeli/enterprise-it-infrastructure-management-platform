"use client";

import { useEffect, useState, type ReactNode } from "react";
import { useRouter } from "next/navigation";

export function AuthGuard({ children }: { children: ReactNode }) {
  const router = useRouter();
  const [authenticated, setAuthenticated] = useState(false);

  useEffect(() => {
    let active = true;

    async function verifySession() {
      try {
        const response = await fetch("/api/v1/session", {
          method: "GET",
          credentials: "same-origin",
          cache: "no-store",
        });

        if (!response.ok) {
          router.replace("/login");
          return;
        }

        const payload = await response.json();
        if (payload.user?.mustChangePassword) {
          router.replace("/change-password");
          return;
        }

        if (active) setAuthenticated(true);
      } catch {
        router.replace("/login");
      }
    }

    void verifySession();
    return () => {
      active = false;
    };
  }, [router]);

  if (!authenticated) {
    return (
      <main className="grid min-h-screen place-items-center px-6">
        <div className="text-center">
          <div className="mx-auto h-8 w-8 animate-spin rounded-full border-2 border-slate-700 border-t-blue-400" />
          <p className="mt-4 text-sm text-slate-400">Checking your session…</p>
        </div>
      </main>
    );
  }

  return <>{children}</>;
}
