"use client";

import { useEffect, useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { ArrowRight, KeyRound } from "lucide-react";

export default function ChangePasswordPage() {
  const router = useRouter();
  const [ready, setReady] = useState(false);
  const [completed, setCompleted] = useState(false);
  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    let active = true;

    async function verifyPasswordChangeState() {
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
        if (!payload.user?.mustChangePassword) {
          router.replace("/");
          return;
        }

        if (active) setReady(true);
      } catch {
        router.replace("/login");
      }
    }

    void verifyPasswordChangeState();
    return () => {
      active = false;
    };
  }, [router]);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");

    if (newPassword !== confirmation) {
      setError("The new passwords do not match.");
      return;
    }

    setBusy(true);
    try {
      const response = await fetch("/api/v1/auth/change-password", {
        method: "POST",
        headers: { "content-type": "application/json" },
        credentials: "same-origin",
        cache: "no-store",
        body: JSON.stringify({ currentPassword, newPassword }),
      });

      if (!response.ok) {
        const payload = await response.json().catch(() => null);
        if (payload?.error?.code === "CURRENT_PASSWORD_INVALID") {
          setError("The current password is incorrect.");
        } else if (payload?.error?.code === "PASSWORD_POLICY_REJECTED") {
          setError("Use a password with at least 14 characters and no control characters.");
        } else {
          setError("Password change failed. Check the API connection and try again.");
        }
        return;
      }

      setCurrentPassword("");
      setNewPassword("");
      setConfirmation("");
      setCompleted(true);
    } catch {
      setError("Unable to contact the authentication service.");
    } finally {
      setBusy(false);
    }
  }

  if (!ready) {
    return (
      <main className="grid min-h-screen place-items-center px-6">
        <p className="text-sm text-slate-400">Verifying your account…</p>
      </main>
    );
  }

  return (
    <main className="grid min-h-screen place-items-center px-5 py-10">
      <section className="panel w-full max-w-md rounded-2xl p-7 sm:p-9">
        <div className="grid h-10 w-10 place-items-center rounded-xl border border-blue-400/20 bg-blue-500/15 text-blue-300">
          <KeyRound size={19} />
        </div>

        {completed ? (
          <>
            <h1 className="mt-6 text-xl font-semibold text-white">Password updated</h1>
            <p className="mt-2 text-sm leading-6 text-slate-400">
              Your previous sessions have been revoked. Sign in again with your new password.
            </p>
            <button
              type="button"
              onClick={() => router.replace("/login")}
              className="mt-7 flex h-11 w-full items-center justify-center gap-2 rounded-lg bg-blue-500 px-4 text-sm font-semibold text-white transition hover:bg-blue-400"
            >
              Go to sign in
              <ArrowRight size={16} />
            </button>
          </>
        ) : (
          <>
            <h1 className="mt-6 text-xl font-semibold text-white">Change your password</h1>
            <p className="mt-2 text-sm leading-6 text-slate-400">
              Your account requires a password change before you can continue.
            </p>

            <form onSubmit={submit} className="mt-8 space-y-5">
              <div>
                <label htmlFor="current-password" className="mb-2 block text-xs font-medium text-slate-300">
                  Current password
                </label>
                <input
                  id="current-password"
                  type="password"
                  autoComplete="current-password"
                  required
                  maxLength={128}
                  value={currentPassword}
                  onChange={(event) => setCurrentPassword(event.target.value)}
                  className="h-11 w-full rounded-lg border border-slate-700 bg-slate-950/70 px-3 text-sm text-slate-100 outline-none focus:border-blue-400"
                />
              </div>

              <div>
                <label htmlFor="new-password" className="mb-2 block text-xs font-medium text-slate-300">
                  New password
                </label>
                <input
                  id="new-password"
                  type="password"
                  autoComplete="new-password"
                  required
                  minLength={14}
                  maxLength={128}
                  value={newPassword}
                  onChange={(event) => setNewPassword(event.target.value)}
                  className="h-11 w-full rounded-lg border border-slate-700 bg-slate-950/70 px-3 text-sm text-slate-100 outline-none focus:border-blue-400"
                />
              </div>

              <div>
                <label htmlFor="confirm-password" className="mb-2 block text-xs font-medium text-slate-300">
                  Confirm new password
                </label>
                <input
                  id="confirm-password"
                  type="password"
                  autoComplete="new-password"
                  required
                  minLength={14}
                  maxLength={128}
                  value={confirmation}
                  onChange={(event) => setConfirmation(event.target.value)}
                  className="h-11 w-full rounded-lg border border-slate-700 bg-slate-950/70 px-3 text-sm text-slate-100 outline-none focus:border-blue-400"
                />
              </div>

              {error && (
                <p role="alert" aria-live="polite" className="rounded-lg border border-rose-400/20 bg-rose-400/10 px-3 py-2.5 text-xs leading-5 text-rose-200">
                  {error}
                </p>
              )}

              <button
                type="submit"
                disabled={busy || !currentPassword || !newPassword || !confirmation}
                className="flex h-11 w-full items-center justify-center gap-2 rounded-lg bg-blue-500 px-4 text-sm font-semibold text-white transition hover:bg-blue-400 disabled:cursor-wait disabled:opacity-50"
              >
                {busy ? "Updating…" : "Update password"}
              </button>
            </form>
          </>
        )}
      </section>
    </main>
  );
}
