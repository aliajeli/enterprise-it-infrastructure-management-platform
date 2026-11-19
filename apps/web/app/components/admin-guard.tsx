"use client";

import { useEffect, useState, type ReactNode } from "react";
import { useRouter } from "next/navigation";

export function AdminGuard({ children }: { children: ReactNode }) {
  const router = useRouter();
  const [allowed, setAllowed] = useState(false);

  useEffect(() => {
    let active = true;

    async function verifyAdministrator() {
      try {
        const response = await fetch("/api/v1/session", {
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
        if (payload.user?.role !== "ADMIN") {
          router.replace("/");
          return;
        }

        if (active) setAllowed(true);
      } catch {
        router.replace("/login");
      }
    }

    void verifyAdministrator();
    return () => {
      active = false;
    };
  }, [router]);

  if (!allowed) {
    return (
      <main className="grid min-h-screen place-items-center px-6">
        <p className="text-sm text-slate-400">Verifying administrator access…</p>
      </main>
    );
  }

  return <>{children}</>;
}
