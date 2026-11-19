import type { Metadata } from "next";
import { AdminGuard } from "../components/admin-guard";
import { UsersClient } from "./users-client";

export const metadata: Metadata = {
  title: "User management",
  description: "Manage platform users and branch access.",
};

export default function UsersPage() {
  return (
    <AdminGuard>
      <main className="min-h-screen">
        <header className="flex h-[72px] items-center border-b border-slate-700/40 px-5 sm:px-8">
          <div>
            <p className="text-xs text-slate-500">Workspace / Administration</p>
            <p className="mt-0.5 text-sm font-semibold text-slate-100">User management</p>
          </div>
        </header>
        <UsersClient />
      </main>
    </AdminGuard>
  );
}
