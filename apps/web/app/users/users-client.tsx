"use client";

import { useCallback, useEffect, useState, type FormEvent } from "react";
import {
  Building2,
  Copy,
  RefreshCw,
  ShieldCheck,
  UserPlus,
  Users,
} from "lucide-react";

type Branch = {
  id: string;
  branchCode: string;
  name: string;
  status: string;
};

type ManagedUser = {
  id: string;
  username: string;
  role: "ADMIN" | "OPERATOR" | "VIEWER";
  status: "ACTIVE" | "DISABLED";
  mustChangePassword: boolean;
  lastLoginAt: string | null;
  createdAt: string;
  branches: Branch[];
};

async function request<T>(url: string, init?: RequestInit): Promise<T> {
  const response = await fetch(url, {
    ...init,
    credentials: "same-origin",
    cache: "no-store",
    headers: {
      ...(init?.body ? { "content-type": "application/json" } : {}),
      ...init?.headers,
    },
  });
  const payload = await response.json().catch(() => null);
  if (!response.ok) {
    throw new Error(payload?.error?.message ?? "The request could not be completed.");
  }
  return payload as T;
}

export function UsersClient() {
  const [users, setUsers] = useState<ManagedUser[]>([]);
  const [branches, setBranches] = useState<Branch[]>([]);
  const [username, setUsername] = useState("");
  const [role, setRole] = useState<"OPERATOR" | "VIEWER">("OPERATOR");
  const [selectedBranches, setSelectedBranches] = useState<string[]>([]);
  const [branchCode, setBranchCode] = useState("");
  const [branchName, setBranchName] = useState("");
  const [draftBranches, setDraftBranches] = useState<Record<string, string[]>>({});
  const [temporaryPassword, setTemporaryPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");

  const refresh = useCallback(async () => {
    const [userResult, branchResult] = await Promise.all([
      request<{ users: ManagedUser[] }>("/api/v1/users"),
      request<{ branches: Branch[] }>("/api/v1/branches"),
    ]);
    setUsers(userResult.users);
    setBranches(branchResult.branches);
  }, []);

  useEffect(() => {
    void refresh().catch((reason: unknown) => {
      setError(reason instanceof Error ? reason.message : "Unable to load user data.");
    });
  }, [refresh]);

  function toggleBranch(
    selected: string[],
    setSelected: (value: string[]) => void,
    branchId: string,
  ) {
    setSelected(
      selected.includes(branchId)
        ? selected.filter((id) => id !== branchId)
        : [...selected, branchId],
    );
  }

  async function createBranch(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setError("");
    setNotice("");
    try {
      await request("/api/v1/branches", {
        method: "POST",
        body: JSON.stringify({ branchCode, name: branchName }),
      });
      setBranchCode("");
      setBranchName("");
      await refresh();
      setNotice("Branch created.");
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Branch creation failed.");
    } finally {
      setBusy(false);
    }
  }

  async function createUser(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setError("");
    setNotice("");
    setTemporaryPassword("");
    try {
      const result = await request<{
        user: ManagedUser;
        temporaryPassword: string;
      }>("/api/v1/users", {
        method: "POST",
        body: JSON.stringify({ username, role, branchIds: selectedBranches }),
      });
      setTemporaryPassword(result.temporaryPassword);
      setUsername("");
      setSelectedBranches([]);
      await refresh();
      setNotice("User created. Copy the temporary password now; it will not be shown again.");
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "User creation failed.");
    } finally {
      setBusy(false);
    }
  }

  async function updateStatus(user: ManagedUser) {
    setBusy(true);
    setError("");
    setNotice("");
    try {
      await request(`/api/v1/users/${user.id}/status`, {
        method: "PATCH",
        body: JSON.stringify({
          status: user.status === "ACTIVE" ? "DISABLED" : "ACTIVE",
        }),
      });
      await refresh();
      setNotice(`Account ${user.status === "ACTIVE" ? "disabled" : "enabled"}.`);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Status update failed.");
    } finally {
      setBusy(false);
    }
  }

  async function updateRole(user: ManagedUser, nextRole: "OPERATOR" | "VIEWER") {
    setBusy(true);
    setError("");
    setNotice("");
    try {
      await request(`/api/v1/users/${user.id}/role`, {
        method: "PATCH",
        body: JSON.stringify({ role: nextRole }),
      });
      await refresh();
      setNotice("User role updated. Their existing sessions were revoked.");
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Role update failed.");
    } finally {
      setBusy(false);
    }
  }

  async function saveBranches(user: ManagedUser) {
    setBusy(true);
    setError("");
    setNotice("");
    try {
      await request(`/api/v1/users/${user.id}/branches`, {
        method: "PUT",
        body: JSON.stringify({
          branchIds: draftBranches[user.id] ?? user.branches.map((branch) => branch.id),
        }),
      });
      await refresh();
      setNotice("Branch access updated.");
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Branch access update failed.");
    } finally {
      setBusy(false);
    }
  }

  async function copyTemporaryPassword() {
    try {
      await navigator.clipboard.writeText(temporaryPassword);
      setNotice("Temporary password copied.");
    } catch {
      setNotice("Copy is unavailable. Select and copy the password manually.");
    }
  }

  return (
    <div className="mx-auto max-w-[1500px] px-5 py-8 sm:px-8 sm:py-10">
      <div className="flex flex-col justify-between gap-4 sm:flex-row sm:items-end">
        <div>
          <div className="mb-3 inline-flex items-center gap-2 rounded-full border border-blue-400/20 bg-blue-400/10 px-3 py-1 text-[11px] font-medium text-blue-200">
            <ShieldCheck size={13} />
            Administrator workspace
          </div>
          <h1 className="text-2xl font-semibold tracking-tight text-white sm:text-3xl">Users and branch access</h1>
          <p className="mt-2 max-w-2xl text-sm leading-6 text-slate-400">
            Provision operator and viewer accounts, assign active branches and revoke access when required.
          </p>
        </div>
        <button
          type="button"
          onClick={() => void refresh().catch((reason: unknown) => setError(reason instanceof Error ? reason.message : "Refresh failed."))}
          disabled={busy}
          className="inline-flex items-center justify-center gap-2 rounded-lg border border-slate-700/60 bg-slate-900/60 px-3 py-2 text-xs text-slate-300 hover:bg-slate-800 disabled:opacity-50"
        >
          <RefreshCw size={14} />
          Refresh
        </button>
      </div>

      {error && <p role="alert" className="mt-5 rounded-lg border border-rose-400/20 bg-rose-400/10 px-4 py-3 text-xs text-rose-200">{error}</p>}
      {notice && <p role="status" className="mt-5 rounded-lg border border-emerald-400/20 bg-emerald-400/10 px-4 py-3 text-xs text-emerald-200">{notice}</p>}

      {temporaryPassword && (
        <section className="mt-6 rounded-xl border border-amber-400/30 bg-amber-400/10 p-5">
          <h2 className="text-sm font-semibold text-amber-100">One-time temporary password</h2>
          <p className="mt-1 text-xs leading-5 text-amber-100/70">
            Copy this password and deliver it to the user through an approved secure channel. It will not be displayed again.
          </p>
          <div className="mt-3 flex flex-col gap-2 sm:flex-row">
            <code className="min-w-0 flex-1 select-all break-all rounded-lg border border-amber-300/20 bg-slate-950/50 px-3 py-3 text-sm text-amber-50">{temporaryPassword}</code>
            <button type="button" onClick={() => void copyTemporaryPassword()} className="inline-flex items-center justify-center gap-2 rounded-lg border border-amber-300/30 px-3 py-2 text-xs text-amber-100 hover:bg-amber-200/10">
              <Copy size={14} /> Copy password
            </button>
          </div>
          <button type="button" onClick={() => setTemporaryPassword("")} className="mt-3 text-[11px] text-amber-100/70 underline">Clear from this screen</button>
        </section>
      )}

      <div className="mt-6 grid gap-5 xl:grid-cols-2">
        <section className="panel rounded-2xl p-5 sm:p-6">
          <div className="flex items-center gap-3">
            <span className="stat-icon"><Building2 size={17} /></span>
            <div>
              <h2 className="text-sm font-semibold text-slate-100">Create branch</h2>
              <p className="mt-1 text-xs text-slate-500">Add a branch record before assigning users.</p>
            </div>
          </div>
          <form onSubmit={createBranch} className="mt-5 grid gap-3 sm:grid-cols-2">
            <label className="text-xs text-slate-400">
              Branch code
              <input value={branchCode} onChange={(event) => setBranchCode(event.target.value.toUpperCase())} required minLength={2} maxLength={32} pattern="[A-Za-z0-9][A-Za-z0-9-]{1,31}" className="mt-2 h-10 w-full rounded-lg border border-slate-700 bg-slate-950/70 px-3 text-sm text-slate-100 outline-none focus:border-blue-400" placeholder="STORE-001" />
            </label>
            <label className="text-xs text-slate-400">
              Branch name
              <input value={branchName} onChange={(event) => setBranchName(event.target.value)} required minLength={2} maxLength={160} className="mt-2 h-10 w-full rounded-lg border border-slate-700 bg-slate-950/70 px-3 text-sm text-slate-100 outline-none focus:border-blue-400" placeholder="Central branch" />
            </label>
            <button type="submit" disabled={busy || !branchCode || !branchName} className="h-10 rounded-lg bg-blue-500 px-4 text-xs font-semibold text-white hover:bg-blue-400 disabled:opacity-50 sm:col-span-2">Create branch</button>
          </form>
          <p className="mt-4 text-[11px] text-slate-500">{branches.length} branch record(s)</p>
        </section>

        <section className="panel rounded-2xl p-5 sm:p-6">
          <div className="flex items-center gap-3">
            <span className="stat-icon"><UserPlus size={17} /></span>
            <div>
              <h2 className="text-sm font-semibold text-slate-100">Create user</h2>
              <p className="mt-1 text-xs text-slate-500">New accounts must change their temporary password at first sign-in.</p>
            </div>
          </div>
          <form onSubmit={createUser} className="mt-5 space-y-4">
            <label className="block text-xs text-slate-400">
              Username
              <input value={username} onChange={(event) => setUsername(event.target.value)} required minLength={3} maxLength={64} className="mt-2 h-10 w-full rounded-lg border border-slate-700 bg-slate-950/70 px-3 text-sm text-slate-100 outline-none focus:border-blue-400" placeholder="operator.name" />
            </label>
            <label className="block text-xs text-slate-400">
              Role
              <select value={role} onChange={(event) => setRole(event.target.value as "OPERATOR" | "VIEWER")} className="mt-2 h-10 w-full rounded-lg border border-slate-700 bg-slate-950/70 px-3 text-sm text-slate-100 outline-none focus:border-blue-400">
                <option value="OPERATOR">Operator — assigned branch scope</option>
                <option value="VIEWER">Viewer — assigned branch read-only</option>
              </select>
            </label>
            <fieldset>
              <legend className="mb-2 text-xs text-slate-400">Assigned branches (required)</legend>
              {branches.length === 0 ? (
                <p className="rounded-lg border border-dashed border-slate-700 px-3 py-4 text-xs text-slate-500">Create at least one branch before provisioning a user.</p>
              ) : (
                <div className="grid max-h-36 gap-2 overflow-y-auto rounded-lg border border-slate-700/60 bg-slate-950/30 p-3 sm:grid-cols-2">
                  {branches.filter((branch) => branch.status === "ACTIVE").map((branch) => (
                    <label key={branch.id} className="flex items-center gap-2 text-xs text-slate-300">
                      <input type="checkbox" checked={selectedBranches.includes(branch.id)} onChange={() => toggleBranch(selectedBranches, setSelectedBranches, branch.id)} className="accent-blue-500" />
                      <span>{branch.branchCode} — {branch.name}</span>
                    </label>
                  ))}
                </div>
              )}
            </fieldset>
            <button type="submit" disabled={busy || !username || selectedBranches.length === 0} className="h-10 w-full rounded-lg bg-blue-500 px-4 text-xs font-semibold text-white hover:bg-blue-400 disabled:opacity-50">Create user and generate temporary password</button>
          </form>
        </section>
      </div>

      <section className="panel mt-6 overflow-hidden rounded-2xl">
        <div className="flex items-center justify-between border-b border-slate-700/50 px-5 py-4 sm:px-6">
          <div className="flex items-center gap-3">
            <span className="stat-icon"><Users size={17} /></span>
            <div>
              <h2 className="text-sm font-semibold text-slate-100">Managed accounts</h2>
              <p className="mt-1 text-xs text-slate-500">{users.length} account(s)</p>
            </div>
          </div>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full min-w-[850px] text-left text-xs">
            <thead className="bg-slate-950/30 text-[10px] uppercase tracking-wider text-slate-500">
              <tr>
                <th className="px-5 py-3 font-medium">User</th>
                <th className="px-5 py-3 font-medium">Role</th>
                <th className="px-5 py-3 font-medium">Status</th>
                <th className="px-5 py-3 font-medium">Branches</th>
                <th className="px-5 py-3 font-medium">Password</th>
                <th className="px-5 py-3 text-right font-medium">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-700/40">
              {users.map((user) => (
                <tr key={user.id} className="align-top text-slate-300">
                  <td className="px-5 py-4">
                    <p className="font-medium text-slate-100">{user.username}</p>
                    <p className="mt-1 text-[10px] text-slate-500">Created {new Date(user.createdAt).toLocaleDateString()}</p>
                  </td>
                  <td className="px-5 py-4">
                    {user.role === "ADMIN" ? (
                      <span className="text-blue-300">Administrator</span>
                    ) : (
                      <select value={user.role} disabled={busy} onChange={(event) => void updateRole(user, event.target.value as "OPERATOR" | "VIEWER")} className="rounded-md border border-slate-700 bg-slate-950/60 px-2 py-1.5 text-xs">
                        <option value="OPERATOR">Operator</option>
                        <option value="VIEWER">Viewer</option>
                      </select>
                    )}
                  </td>
                  <td className="px-5 py-4">
                    <span className={user.status === "ACTIVE" ? "text-emerald-300" : "text-slate-500"}>{user.status}</span>
                  </td>
                  <td className="px-5 py-4">
                    {user.role === "ADMIN" ? (
                      <span className="text-slate-500">Global scope</span>
                    ) : (
                    <>
                    <div className="flex flex-wrap gap-1">
                      {user.branches.map((branch) => <span key={branch.id} className="rounded-md border border-slate-700/70 px-2 py-1 text-[10px]">{branch.branchCode}</span>)}
                    </div>
                    <details className="mt-2">
                      <summary className="cursor-pointer text-[10px] text-blue-300">Edit branch access</summary>
                      <div className="mt-2 space-y-2 rounded-lg border border-slate-700/60 bg-slate-950/30 p-3">
                        {branches.filter((branch) => branch.status === "ACTIVE").map((branch) => {
                          const selected = draftBranches[user.id] ?? user.branches.map((item) => item.id);
                          return (
                            <label key={branch.id} className="flex items-center gap-2 text-[11px]">
                              <input type="checkbox" checked={selected.includes(branch.id)} onChange={() => toggleBranch(selected, (value) => setDraftBranches((current) => ({ ...current, [user.id]: value })), branch.id)} className="accent-blue-500" />
                              {branch.branchCode} — {branch.name}
                            </label>
                          );
                        })}
                        <button type="button" onClick={() => void saveBranches(user)} disabled={busy || (draftBranches[user.id] ?? user.branches.map((item) => item.id)).length === 0} className="rounded-md bg-blue-500 px-3 py-1.5 text-[10px] font-semibold text-white disabled:opacity-50">Save branches</button>
                      </div>
                    </details>
                    </>
                    )}
                  </td>
                  <td className="px-5 py-4">{user.mustChangePassword ? <span className="text-amber-300">Change required</span> : <span className="text-slate-500">Current</span>}</td>
                  <td className="px-5 py-4 text-right">
                    {user.role !== "ADMIN" && (
                      <button type="button" onClick={() => void updateStatus(user)} disabled={busy} className="rounded-md border border-slate-700 px-2.5 py-1.5 text-[10px] hover:bg-slate-800 disabled:opacity-50">{user.status === "ACTIVE" ? "Disable" : "Enable"}</button>
                    )}
                  </td>
                </tr>
              ))}
              {users.length === 0 && (
                <tr><td colSpan={6} className="px-5 py-10 text-center text-xs text-slate-500">No managed accounts found.</td></tr>
              )}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}
