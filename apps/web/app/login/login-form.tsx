"use client";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { ArrowRight } from "lucide-react";

export function LoginForm() {
  const router = useRouter();
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setError("");

    try {
      const response = await fetch("/api/v1/auth/login", {
        method: "POST",
        headers: { "content-type": "application/json" },
        credentials: "same-origin",
        cache: "no-store",
        body: JSON.stringify({ username, password }),
      });

      if (!response.ok) {
        const payload = await response.json().catch(() => null);
        if (response.status === 429 || payload?.error?.code === "RATE_LIMITED") {
          setError("Too many sign-in attempts. Wait before trying again.");
        } else if (payload?.error?.code === "INVALID_CREDENTIALS") {
          setError("Invalid username or password.");
        } else {
          setError("Sign-in failed. Check the API connection and try again.");
        }
        return;
      }

      setPassword("");
      router.replace("/");
      router.refresh();
    } catch {
      setError("Unable to contact the authentication service.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <form onSubmit={submit} className="mt-8 space-y-5">
      <div>
        <label htmlFor="username" className="mb-2 block text-xs font-medium text-slate-300">
          Username
        </label>
        <input
          id="username"
          name="username"
          type="text"
          autoComplete="username"
          required
          minLength={3}
          maxLength={64}
          value={username}
          onChange={(event) => setUsername(event.target.value)}
          className="h-11 w-full rounded-lg border border-slate-700 bg-slate-950/70 px-3 text-sm text-slate-100 outline-none transition placeholder:text-slate-600 focus:border-blue-400 focus:ring-2 focus:ring-blue-400/15"
          placeholder="Enter your username"
        />
      </div>

      <div>
        <label htmlFor="password" className="mb-2 block text-xs font-medium text-slate-300">
          Password
        </label>
        <input
          id="password"
          name="password"
          type="password"
          autoComplete="current-password"
          required
          minLength={14}
          maxLength={128}
          value={password}
          onChange={(event) => setPassword(event.target.value)}
          className="h-11 w-full rounded-lg border border-slate-700 bg-slate-950/70 px-3 text-sm text-slate-100 outline-none transition placeholder:text-slate-600 focus:border-blue-400 focus:ring-2 focus:ring-blue-400/15"
          placeholder="Enter your password"
        />
      </div>

      {error && (
        <p role="alert" aria-live="polite" className="rounded-lg border border-rose-400/20 bg-rose-400/10 px-3 py-2.5 text-xs leading-5 text-rose-200">
          {error}
        </p>
      )}

      <button
        type="submit"
        disabled={busy || !username || !password}
        className="flex h-11 w-full items-center justify-center gap-2 rounded-lg bg-blue-500 px-4 text-sm font-semibold text-white transition hover:bg-blue-400 disabled:cursor-wait disabled:opacity-50"
      >
        {busy ? "Signing in…" : "Sign in"}
        {!busy && <ArrowRight size={16} />}
      </button>
    </form>
  );
}
