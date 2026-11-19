"use client";

import { useCallback, useEffect, useMemo, useState, type FormEvent } from "react";
import { AuthGuard } from "../components/auth-guard";
import { LogoutButton } from "../components/logout-button";
import {
  ArrowLeft, Boxes, Cable, CircleAlert, LoaderCircle, Plus, RefreshCw,
  Search, Server, ShieldCheck, X,
} from "lucide-react";
import Link from "next/link";

type AssetKind =
  | "COMPUTER" | "SERVER" | "SWITCH" | "ROUTER" | "FIREWALL"
  | "NVR" | "CAMERA" | "PRINTER" | "POS" | "UPS" | "OTHER";

type Branch = { id: string; branchCode: string; name: string; status: string };
type Observation = {
  source: string;
  observedAt: string;
  adminState: string;
  operState: string;
  vlanId: number | null;
  ipAddress: string | null;
  macAddress: string | null;
  speedMbps: number | null;
};
type Port = {
  id: string;
  ifIndex: number;
  name: string | null;
  alias: string | null;
  description: string | null;
  configuredVlanId: number | null;
  configuredTaggedVlans: number[];
  connectedDeviceLabel: string | null;
  version: number;
  observations: Observation[];
};
type Asset = {
  id: string;
  branchId: string;
  assetCode: string;
  name: string;
  kind: AssetKind;
  status: string;
  hostname: string | null;
  primaryIp: string | null;
  macAddress: string | null;
  vendor: string | null;
  model: string | null;
  location: string | null;
  description: string | null;
  version: number;
  switch: null | { sysName: string | null; firmwareVersion: string | null; reportedPortCount: number | null; portCount: number };
};

const kinds: AssetKind[] = [
  "COMPUTER", "SERVER", "SWITCH", "ROUTER", "FIREWALL",
  "NVR", "CAMERA", "PRINTER", "POS", "UPS", "OTHER",
];
const inputClass = "w-full rounded-lg border border-slate-700 bg-slate-950/70 px-3 py-2.5 text-sm text-slate-100 outline-none transition placeholder:text-slate-600 focus:border-blue-400";
const labelClass = "mb-1.5 block text-[11px] font-medium text-slate-400";

async function requestJson<T>(url: string, init?: RequestInit): Promise<T> {
  const headers = new Headers(init?.headers);
  if (init?.body && !headers.has("content-type")) headers.set("content-type", "application/json");
  const response = await fetch(url, {
    ...init,
    credentials: "same-origin",
    cache: "no-store",
    headers,
  });
  if (!response.ok) {
    const payload = await response.json().catch(() => null) as { error?: { message?: string } } | null;
    throw new Error(payload?.error?.message ?? `Request failed (${response.status})`);
  }
  if (response.status === 204) return undefined as T;
  return response.json() as Promise<T>;
}

function InventoryContent() {
  const [branches, setBranches] = useState<Branch[]>([]);
  const [branchId, setBranchId] = useState("");
  const [assets, setAssets] = useState<Asset[]>([]);
  const [search, setSearch] = useState("");
  const [kind, setKind] = useState("");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [showCreate, setShowCreate] = useState(false);
  const [selectedSwitch, setSelectedSwitch] = useState<Asset | null>(null);
  const [ports, setPorts] = useState<Port[]>([]);
  const [portsLoading, setPortsLoading] = useState(false);
  const [portSaving, setPortSaving] = useState(false);
  const [assetForm, setAssetForm] = useState({
    assetCode: "", name: "", kind: "SWITCH" as AssetKind, primaryIp: "",
    hostname: "", vendor: "", model: "", location: "",
    sysName: "", firmwareVersion: "", reportedPortCount: "24",
  });
  const [portForm, setPortForm] = useState({
    ifIndex: "", name: "", alias: "", description: "",
    configuredVlanId: "", configuredTaggedVlans: "", connectedDeviceLabel: "",
  });

  const loadBranches = useCallback(async () => {
    const payload = await requestJson<{ branches: Branch[] }>("/api/v1/branches/accessible");
    setBranches(payload.branches);
    setBranchId((current) => current && payload.branches.some((branch) => branch.id === current)
      ? current : payload.branches[0]?.id ?? "");
  }, []);

  const loadAssets = useCallback(async () => {
    if (!branchId) {
      setAssets([]);
      setLoading(false);
      return;
    }
    setLoading(true);
    try {
      const params = new URLSearchParams({ branchId, limit: "100" });
      if (kind) params.set("kind", kind);
      if (search.trim()) params.set("q", search.trim());
      const payload = await requestJson<{ assets: Asset[] }>(`/api/v1/inventory/assets?${params.toString()}`);
      setAssets(payload.assets);
      setError("");
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not load inventory.");
    } finally {
      setLoading(false);
    }
  }, [branchId, kind, search]);

  // The effect starts asynchronous network loading; state updates occur after the request resolves.
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => {
    void loadBranches().catch((cause: unknown) => {
      setError(cause instanceof Error ? cause.message : "Could not load accessible branches.");
      setLoading(false);
    });
  }, [loadBranches]);

  // loadAssets performs asynchronous network I/O before updating the rendered inventory state.
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void loadAssets(); }, [loadAssets]);

  const selectedBranch = useMemo(
    () => branches.find((branch) => branch.id === branchId),
    [branches, branchId],
  );

  async function openSwitch(asset: Asset) {
    setSelectedSwitch(asset);
    setPortsLoading(true);
    setError("");
    try {
      const payload = await requestJson<{ ports: Port[] }>(
        `/api/v1/inventory/assets/${asset.id}/switch-ports`,
      );
      setPorts(payload.ports);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not load switch ports.");
      setPorts([]);
    } finally {
      setPortsLoading(false);
    }
  }

  async function createAsset(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!branchId) return;
    setSaving(true);
    setError("");
    setNotice("");
    try {
      const payload: Record<string, unknown> = {
        branchId,
        assetCode: assetForm.assetCode,
        name: assetForm.name,
        kind: assetForm.kind,
        primaryIp: assetForm.primaryIp || undefined,
        hostname: assetForm.hostname || undefined,
        vendor: assetForm.vendor || undefined,
        model: assetForm.model || undefined,
        location: assetForm.location || undefined,
      };
      if (assetForm.kind === "SWITCH") {
        payload.switch = {
          sysName: assetForm.sysName || undefined,
          firmwareVersion: assetForm.firmwareVersion || undefined,
          reportedPortCount: assetForm.reportedPortCount ? Number(assetForm.reportedPortCount) : undefined,
        };
      }
      await requestJson("/api/v1/inventory/assets", { method: "POST", body: JSON.stringify(payload) });
      setShowCreate(false);
      setAssetForm({
        assetCode: "", name: "", kind: "SWITCH", primaryIp: "", hostname: "",
        vendor: "", model: "", location: "", sysName: "", firmwareVersion: "", reportedPortCount: "24",
      });
      setNotice("Asset created successfully.");
      await loadAssets();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not create asset.");
    } finally {
      setSaving(false);
    }
  }

  async function createPort(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!selectedSwitch) return;
    const ifIndex = Number(portForm.ifIndex);
    const vlan = portForm.configuredVlanId ? Number(portForm.configuredVlanId) : undefined;
    const tagged = portForm.configuredTaggedVlans.trim()
      ? portForm.configuredTaggedVlans.split(",").map((value) => Number(value.trim()))
      : [];
    if (!Number.isInteger(ifIndex) || ifIndex < 1 || (vlan !== undefined && (!Number.isInteger(vlan) || vlan < 1 || vlan > 4094)) ||
        tagged.some((value) => !Number.isInteger(value) || value < 1 || value > 4094)) {
      setError("Enter a valid interface index and VLAN IDs between 1 and 4094.");
      return;
    }
    setPortSaving(true);
    setError("");
    try {
      await requestJson(`/api/v1/inventory/assets/${selectedSwitch.id}/switch-ports`, {
        method: "POST",
        body: JSON.stringify({
          ifIndex,
          name: portForm.name || undefined,
          alias: portForm.alias || undefined,
          description: portForm.description || undefined,
          configuredVlanId: vlan,
          configuredTaggedVlans: tagged,
          connectedDeviceLabel: portForm.connectedDeviceLabel || undefined,
        }),
      });
      const payload = await requestJson<{ ports: Port[] }>(
        `/api/v1/inventory/assets/${selectedSwitch.id}/switch-ports`,
      );
      setPorts(payload.ports);
      setPortForm({ ifIndex: "", name: "", alias: "", description: "", configuredVlanId: "", configuredTaggedVlans: "", connectedDeviceLabel: "" });
      setNotice("Switch-port metadata saved. No switch configuration was changed.");
      await loadAssets();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not save switch-port metadata.");
    } finally {
      setPortSaving(false);
    }
  }

  return (
    <main className="min-h-screen">
      <header className="flex h-[72px] items-center justify-between border-b border-slate-700/40 px-5 sm:px-8">
        <div className="flex items-center gap-3">
          <Link href="/" aria-label="Back to overview" className="grid h-9 w-9 place-items-center rounded-lg border border-slate-700/60 bg-slate-900 text-slate-300 hover:text-white">
            <ArrowLeft size={17} />
          </Link>
          <div>
            <p className="text-xs text-slate-500">Workspace / Inventory</p>
            <h1 className="text-sm font-semibold text-slate-100">Device inventory</h1>
          </div>
        </div>
        <LogoutButton />
      </header>

      <div className="mx-auto max-w-[1500px] px-5 py-8 sm:px-8">
        <div className="flex flex-col justify-between gap-4 md:flex-row md:items-end">
          <div>
            <p className="text-[10px] font-semibold uppercase tracking-[.18em] text-blue-300">M2 · Inventory foundation</p>
            <h2 className="mt-2 text-2xl font-semibold tracking-tight text-white sm:text-3xl">Branch equipment</h2>
            <p className="mt-2 max-w-2xl text-sm leading-6 text-slate-400">
              Register equipment and maintain switch-port labels, VLAN metadata and connected-device notes.
            </p>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <select aria-label="Branch" value={branchId} onChange={(event) => setBranchId(event.target.value)} className="min-w-56 rounded-lg border border-slate-700 bg-slate-900 px-3 py-2.5 text-sm text-slate-100">
              {branches.length === 0 && <option value="">No accessible branches</option>}
              {branches.map((branch) => <option key={branch.id} value={branch.id}>{branch.branchCode} · {branch.name}</option>)}
            </select>
            <button type="button" onClick={() => void loadAssets()} disabled={loading || !branchId} className="grid h-10 w-10 place-items-center rounded-lg border border-slate-700 bg-slate-900 text-slate-300 disabled:opacity-40" aria-label="Refresh inventory">
              <RefreshCw size={16} />
            </button>
            <button type="button" onClick={() => setShowCreate(true)} disabled={!branchId} className="inline-flex items-center gap-2 rounded-lg bg-blue-500 px-4 py-2.5 text-sm font-semibold text-white hover:bg-blue-400 disabled:opacity-40">
              <Plus size={16} /> Add equipment
            </button>
          </div>
        </div>

        <div className="mt-7 grid gap-3 sm:grid-cols-3">
          <div className="panel rounded-xl p-4"><p className="text-xs text-slate-500">Assets in this branch</p><p className="mt-2 text-2xl font-semibold text-white">{assets.length}</p></div>
          <div className="panel rounded-xl p-4"><p className="text-xs text-slate-500">Switches</p><p className="mt-2 text-2xl font-semibold text-white">{assets.filter((asset) => asset.kind === "SWITCH").length}</p></div>
          <div className="panel rounded-xl p-4"><p className="text-xs text-slate-500">Branch</p><p className="mt-2 truncate text-lg font-semibold text-white">{selectedBranch?.name ?? "—"}</p></div>
        </div>

        {error && <div role="alert" className="mt-5 flex items-start gap-2 rounded-lg border border-rose-500/30 bg-rose-500/10 p-3 text-sm text-rose-200"><CircleAlert size={17} className="mt-0.5 shrink-0" />{error}</div>}
        {notice && <div role="status" className="mt-5 rounded-lg border border-emerald-500/25 bg-emerald-500/10 p-3 text-sm text-emerald-200">{notice}</div>}

        <section className="panel mt-6 overflow-hidden rounded-2xl">
          <div className="flex flex-col gap-3 border-b border-slate-700/50 p-4 sm:flex-row sm:items-center sm:justify-between">
            <div className="flex items-center gap-2 text-sm font-semibold text-slate-100"><Boxes size={17} className="text-blue-300" /> Equipment register</div>
            <div className="flex flex-col gap-2 sm:flex-row">
              <div className="flex items-center gap-2 rounded-lg border border-slate-700 bg-slate-950/60 px-3">
                <Search size={15} className="text-slate-500" />
                <input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search name, code, hostname or IP" className="w-full bg-transparent py-2 text-xs text-slate-100 outline-none placeholder:text-slate-600 sm:w-64" />
              </div>
              <select aria-label="Filter by equipment type" value={kind} onChange={(event) => setKind(event.target.value)} className="rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-xs text-slate-200">
                <option value="">All types</option>
                {kinds.map((value) => <option key={value} value={value}>{value}</option>)}
              </select>
            </div>
          </div>
          {loading ? (
            <div className="flex min-h-48 items-center justify-center gap-2 text-sm text-slate-400"><LoaderCircle size={17} className="animate-spin" /> Loading inventory…</div>
          ) : assets.length === 0 ? (
            <div className="flex min-h-56 flex-col items-center justify-center px-6 text-center">
              <Server size={25} className="text-slate-500" />
              <p className="mt-3 text-sm font-medium text-slate-200">No equipment found</p>
              <p className="mt-1 max-w-md text-xs leading-5 text-slate-500">Add the first asset for this branch, or change the search and type filters.</p>
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full min-w-[850px] text-left text-xs">
                <thead className="bg-slate-950/50 text-[10px] uppercase tracking-wider text-slate-500">
                  <tr><th className="px-5 py-3">Asset</th><th className="px-4 py-3">Type</th><th className="px-4 py-3">Address</th><th className="px-4 py-3">Vendor / model</th><th className="px-4 py-3">Location</th><th className="px-4 py-3">Details</th></tr>
                </thead>
                <tbody className="divide-y divide-slate-800/80">
                  {assets.map((asset) => (
                    <tr key={asset.id} className="hover:bg-slate-900/40">
                      <td className="px-5 py-4"><p className="font-semibold text-slate-100">{asset.name}</p><p className="mt-1 font-mono text-[10px] text-slate-500">{asset.assetCode}</p></td>
                      <td className="px-4 py-4"><span className="rounded-md border border-slate-700 px-2 py-1 text-[10px] text-slate-300">{asset.kind}</span></td>
                      <td className="px-4 py-4"><p className="font-mono text-slate-300">{asset.primaryIp ?? "—"}</p><p className="mt-1 text-[10px] text-slate-500">{asset.hostname ?? asset.macAddress ?? "No hostname / MAC"}</p></td>
                      <td className="px-4 py-4 text-slate-300">{[asset.vendor, asset.model].filter(Boolean).join(" ") || "—"}</td>
                      <td className="px-4 py-4 text-slate-400">{asset.location ?? "—"}</td>
                      <td className="px-4 py-4">{asset.kind === "SWITCH" ? <button type="button" onClick={() => void openSwitch(asset)} className="inline-flex items-center gap-1.5 rounded-md border border-blue-400/25 bg-blue-400/10 px-2.5 py-1.5 text-[10px] font-medium text-blue-200 hover:bg-blue-400/20"><Cable size={13} /> {asset.switch?.portCount ?? 0} ports</button> : <span className="text-slate-600">—</span>}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
          <div className="border-t border-slate-700/50 px-5 py-3 text-[10px] text-slate-500">Showing up to 100 matching assets · Source: application inventory · No live discovery is running</div>
        </section>
      </div>

      {showCreate && (
        <div className="fixed inset-0 z-40 flex items-center justify-center overflow-y-auto bg-black/70 p-4">
          <section role="dialog" aria-modal="true" aria-labelledby="create-asset-title" className="my-8 w-full max-w-2xl rounded-2xl border border-slate-700 bg-slate-950 p-5 shadow-2xl sm:p-7">
            <div className="flex items-center justify-between"><div><p className="text-[10px] uppercase tracking-widest text-blue-300">Inventory</p><h3 id="create-asset-title" className="mt-1 text-lg font-semibold text-white">Add equipment</h3></div><button type="button" onClick={() => setShowCreate(false)} aria-label="Close" className="rounded-lg p-2 text-slate-400 hover:bg-slate-800"><X size={18} /></button></div>
            <form onSubmit={createAsset} className="mt-5 grid gap-4 sm:grid-cols-2">
              <label><span className={labelClass}>Asset code *</span><input required minLength={2} maxLength={64} value={assetForm.assetCode} onChange={(event) => setAssetForm({ ...assetForm, assetCode: event.target.value })} className={inputClass} placeholder="SW-HQ-01" /></label>
              <label><span className={labelClass}>Display name *</span><input required minLength={2} maxLength={160} value={assetForm.name} onChange={(event) => setAssetForm({ ...assetForm, name: event.target.value })} className={inputClass} placeholder="Core switch" /></label>
              <label><span className={labelClass}>Equipment type *</span><select value={assetForm.kind} onChange={(event) => setAssetForm({ ...assetForm, kind: event.target.value as AssetKind })} className={inputClass}>{kinds.map((value) => <option key={value} value={value}>{value}</option>)}</select></label>
              <label><span className={labelClass}>Management IP</span><input value={assetForm.primaryIp} onChange={(event) => setAssetForm({ ...assetForm, primaryIp: event.target.value })} className={inputClass} placeholder="192.168.1.10" /></label>
              <label><span className={labelClass}>Hostname</span><input value={assetForm.hostname} onChange={(event) => setAssetForm({ ...assetForm, hostname: event.target.value })} className={inputClass} /></label>
              <label><span className={labelClass}>Vendor</span><input value={assetForm.vendor} onChange={(event) => setAssetForm({ ...assetForm, vendor: event.target.value })} className={inputClass} placeholder="Cisco / MikroTik / Hikvision" /></label>
              <label><span className={labelClass}>Model</span><input value={assetForm.model} onChange={(event) => setAssetForm({ ...assetForm, model: event.target.value })} className={inputClass} /></label>
              <label><span className={labelClass}>Physical location</span><input value={assetForm.location} onChange={(event) => setAssetForm({ ...assetForm, location: event.target.value })} className={inputClass} placeholder="Rack 02 / Store room" /></label>
              {assetForm.kind === "SWITCH" && <div className="sm:col-span-2 rounded-xl border border-slate-700/70 bg-slate-900/50 p-4"><p className="mb-3 text-xs font-semibold text-slate-200">Switch profile</p><div className="grid gap-3 sm:grid-cols-3"><label><span className={labelClass}>System name</span><input value={assetForm.sysName} onChange={(event) => setAssetForm({ ...assetForm, sysName: event.target.value })} className={inputClass} /></label><label><span className={labelClass}>Firmware</span><input value={assetForm.firmwareVersion} onChange={(event) => setAssetForm({ ...assetForm, firmwareVersion: event.target.value })} className={inputClass} /></label><label><span className={labelClass}>Reported ports</span><input type="number" min="0" max="4096" value={assetForm.reportedPortCount} onChange={(event) => setAssetForm({ ...assetForm, reportedPortCount: event.target.value })} className={inputClass} /></label></div></div>}
              <div className="flex justify-end gap-2 sm:col-span-2"><button type="button" onClick={() => setShowCreate(false)} className="rounded-lg border border-slate-700 px-4 py-2 text-xs text-slate-300">Cancel</button><button disabled={saving} className="inline-flex items-center gap-2 rounded-lg bg-blue-500 px-4 py-2 text-xs font-semibold text-white disabled:opacity-50">{saving && <LoaderCircle size={14} className="animate-spin" />} Save asset</button></div>
            </form>
          </section>
        </div>
      )}

      {selectedSwitch && (
        <div className="fixed inset-0 z-40 flex items-center justify-center overflow-y-auto bg-black/70 p-4">
          <section role="dialog" aria-modal="true" aria-labelledby="switch-ports-title" className="my-8 w-full max-w-5xl rounded-2xl border border-slate-700 bg-slate-950 p-5 shadow-2xl sm:p-7">
            <div className="flex items-start justify-between gap-3"><div><p className="text-[10px] uppercase tracking-widest text-blue-300">Switch inventory</p><h3 id="switch-ports-title" className="mt-1 text-lg font-semibold text-white">{selectedSwitch.name}</h3><p className="mt-1 text-xs text-slate-500">{selectedSwitch.primaryIp ?? "No management IP"} · {selectedSwitch.vendor ?? ""} {selectedSwitch.model ?? ""}</p></div><button type="button" onClick={() => setSelectedSwitch(null)} aria-label="Close switch ports" className="rounded-lg p-2 text-slate-400 hover:bg-slate-800"><X size={18} /></button></div>
            <div className="mt-5 overflow-x-auto rounded-xl border border-slate-800">
              {portsLoading ? <div className="p-8 text-center text-sm text-slate-400">Loading switch ports…</div> : ports.length === 0 ? <div className="p-8 text-center text-sm text-slate-500">No port metadata recorded yet.</div> : <table className="w-full min-w-[720px] text-left text-xs"><thead className="bg-slate-900 text-[10px] uppercase tracking-wider text-slate-500"><tr><th className="px-4 py-3">Interface</th><th className="px-4 py-3">Alias / device</th><th className="px-4 py-3">Configured VLAN</th><th className="px-4 py-3">Observed state</th><th className="px-4 py-3">Observed IP / MAC</th></tr></thead><tbody className="divide-y divide-slate-800">{ports.map((port) => { const observation = port.observations[0]; return <tr key={port.id}><td className="px-4 py-3"><p className="font-mono text-slate-200">{port.name ?? `ifIndex ${port.ifIndex}`}</p><p className="mt-1 text-[10px] text-slate-600">Index {port.ifIndex}</p></td><td className="px-4 py-3"><p className="text-slate-200">{port.alias ?? "—"}</p><p className="mt-1 text-[10px] text-slate-500">{port.connectedDeviceLabel ?? port.description ?? "—"}</p></td><td className="px-4 py-3 text-slate-300">{port.configuredVlanId ?? "—"}{port.configuredTaggedVlans.length ? ` / tagged ${port.configuredTaggedVlans.join(", ")}` : ""}</td><td className="px-4 py-3"><span className={observation?.operState === "UP" ? "text-emerald-300" : observation?.operState === "DOWN" ? "text-rose-300" : "text-slate-500"}>{observation?.operState ?? "Not observed"}</span><p className="mt-1 text-[10px] text-slate-600">{observation ? `${observation.source} · ${new Date(observation.observedAt).toLocaleString()}` : "No observation"}</p></td><td className="px-4 py-3 font-mono text-[10px] text-slate-400">{observation?.ipAddress ?? "—"}<p className="mt-1">{observation?.macAddress ?? "—"}</p></td></tr>; })}</tbody></table>}
            </div>
            <div className="mt-5 rounded-xl border border-slate-700/70 bg-slate-900/40 p-4">
              <h4 className="text-xs font-semibold text-slate-200">Add port metadata</h4>
              <form onSubmit={createPort} className="mt-3 grid gap-3 sm:grid-cols-3">
                <label><span className={labelClass}>ifIndex *</span><input required type="number" min="1" max="65535" value={portForm.ifIndex} onChange={(event) => setPortForm({ ...portForm, ifIndex: event.target.value })} className={inputClass} /></label>
                <label><span className={labelClass}>Interface name</span><input value={portForm.name} onChange={(event) => setPortForm({ ...portForm, name: event.target.value })} className={inputClass} placeholder="Gi1/0/1" /></label>
                <label><span className={labelClass}>Alias</span><input value={portForm.alias} onChange={(event) => setPortForm({ ...portForm, alias: event.target.value })} className={inputClass} placeholder="Checkout 01" /></label>
                <label><span className={labelClass}>Access VLAN</span><input type="number" min="1" max="4094" value={portForm.configuredVlanId} onChange={(event) => setPortForm({ ...portForm, configuredVlanId: event.target.value })} className={inputClass} /></label>
                <label><span className={labelClass}>Tagged VLANs</span><input value={portForm.configuredTaggedVlans} onChange={(event) => setPortForm({ ...portForm, configuredTaggedVlans: event.target.value })} className={inputClass} placeholder="7, 30, 40" /></label>
                <label><span className={labelClass}>Connected device</span><input value={portForm.connectedDeviceLabel} onChange={(event) => setPortForm({ ...portForm, connectedDeviceLabel: event.target.value })} className={inputClass} placeholder="POS-01" /></label>
                <label className="sm:col-span-3"><span className={labelClass}>Description</span><input value={portForm.description} onChange={(event) => setPortForm({ ...portForm, description: event.target.value })} className={inputClass} placeholder="Main checkout terminal" /></label>
                <div className="flex flex-wrap items-center justify-between gap-2 sm:col-span-3"><p className="text-[10px] text-slate-500">This stores inventory metadata only. It does not configure the physical switch.</p><button disabled={portSaving} className="inline-flex items-center gap-2 rounded-lg bg-blue-500 px-4 py-2 text-xs font-semibold text-white disabled:opacity-50">{portSaving && <LoaderCircle size={14} className="animate-spin" />} Save port metadata</button></div>
              </form>
            </div>
          </section>
        </div>
      )}

      <footer className="mx-auto max-w-[1500px] px-5 pb-8 text-[10px] text-slate-600 sm:px-8">
        <span className="inline-flex items-center gap-1.5"><ShieldCheck size={12} /> Role and branch access are enforced by the API. Displayed port state is the latest recorded observation, not a live poll.</span>
      </footer>
    </main>
  );
}

export default function InventoryPage() {
  return <AuthGuard><InventoryContent /></AuthGuard>;
}
