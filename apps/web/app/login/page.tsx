import type { Metadata } from "next";
import { Command, LockKeyhole } from "lucide-react";
import { LoginForm } from "./login-form";

export const metadata: Metadata = {
  title: "Sign in",
  description: "Sign in to the Infrastructure Control Center.",
};

export default function LoginPage() {
  return (
    <main className="grid min-h-screen place-items-center px-5 py-10">
      <section className="panel w-full max-w-md rounded-2xl p-7 sm:p-9">
        <div className="flex items-center gap-3">
          <div className="grid h-10 w-10 place-items-center rounded-xl border border-blue-400/20 bg-blue-500/15 text-blue-300">
            <Command size={20} />
          </div>
          <div>
            <p className="text-sm font-semibold tracking-tight text-white">
              Infrastructure
            </p>
            <p className="mt-0.5 text-[11px] text-slate-500">
              CONTROL CENTER
            </p>
          </div>
        </div>

        <div className="mt-9">
          <div className="mb-4 grid h-10 w-10 place-items-center rounded-xl border border-slate-700/70 bg-slate-900 text-slate-300">
            <LockKeyhole size={18} />
          </div>
          <h1 className="text-xl font-semibold tracking-tight text-white">
            Sign in to your workspace
          </h1>
          <p className="mt-2 text-sm leading-6 text-slate-400">
            Use your platform account to access infrastructure operations.
          </p>
        </div>

        <LoginForm />

        <p className="mt-7 border-t border-slate-700/50 pt-5 text-[11px] leading-5 text-slate-500">
          Access is managed by your platform administrator. There is no public
          self-registration.
        </p>
      </section>
    </main>
  );
}
