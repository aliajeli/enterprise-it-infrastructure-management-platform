"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { Users } from "lucide-react";

export function AdminNavLink() {
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    let active = true;
    void fetch("/api/v1/session", {
      credentials: "same-origin",
      cache: "no-store",
    })
      .then(async (response) => {
        if (!response.ok) return null;
        return response.json();
      })
      .then((payload) => {
        if (active && payload?.user?.role === "ADMIN") setVisible(true);
      })
      .catch(() => undefined);

    return () => {
      active = false;
    };
  }, []);

  if (!visible) return null;

  return (
    <Link href="/users" className="sidebar-link">
      <Users size={17} strokeWidth={1.8} />
      <span>User management</span>
      <span className="ml-auto text-[9px] uppercase tracking-wider text-blue-300">Admin</span>
    </Link>
  );
}
