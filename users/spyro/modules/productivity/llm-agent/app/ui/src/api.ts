/**
 * The UI's client for the llm-agent server API. All calls go to the same-origin
 * `/api/*` endpoints; in dev the Vite proxy forwards them to the server.
 */

export interface SpecProfile {
  enabled?: boolean
  specType?: string
  draftModel?: string
  draftTokensMax?: number
  draftPMin?: number
  draftPSplit?: number
  draftGpuLayers?: number | "auto" | "all"
  draftCacheTypeK?: string
  draftCacheTypeV?: string
}

export interface ModelOptions {
  ctxSize?: number
  outputLimit?: number
  gpuLayers?: number
  cacheType?: string
  cacheTypeK?: string
  cacheTypeV?: string
  reasoningBudget?: number | null
  ttl?: number
  temperature?: number
  topP?: number
  topK?: number
  minP?: number
  specProfile?: SpecProfile
  extraArgs?: string[]
  templateOverride?: string
}

export interface ModelEntry {
  displayName: string
  hfRef: string
  options?: ModelOptions
  _comment?: string
}

export interface RegistryData {
  version: number
  default: { provider: string; name: string }
  unloadPolicy: { idleThresholdSeconds: number; settleSeconds: number }
  local: Record<string, ModelEntry>
  cloud: Record<string, string>
  opencode: { mcp?: Record<string, unknown>; plugin?: string[] }
}

export interface Artifacts {
  configYaml: string
  opencodeJson: string
  unloadPolicyJson: string
}

export interface BackendStatus {
  up: boolean
  running: Array<{ model: string; state: string }>
  version: string | null
}

export interface Heartbeat {
  present: boolean
  at?: number
  ageMs: number | null
  pid?: number
  instanceId?: string
}

export interface LeaseInfo {
  instanceId: string
  pid: number
  alive: boolean
  busySince: number | null
  lastLocalActivityAt: number | null
}

export interface LeaseStatus {
  readable: boolean
  error?: string
  leases: LeaseInfo[]
  busy: boolean
  busyLeases: LeaseInfo[]
}

export interface StatusResponse {
  backend: BackendStatus
  heartbeat: Heartbeat
  leases: LeaseStatus
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(path, init)
  const text = await res.text()
  let body: unknown
  try {
    body = text === "" ? null : JSON.parse(text)
  } catch {
    body = { error: text }
  }
  if (!res.ok) {
    const msg = body && typeof body === "object" && "errors" in body
      ? (body as { errors: string[] }).errors.join("; ")
      : `HTTP ${res.status}`
    throw new Error(msg)
  }
  return body as T
}

const json = (body: unknown): RequestInit => ({
  headers: { "content-type": "application/json" },
  body: JSON.stringify(body),
})

/**
 * Map the core validator's flat error strings to the form fields they concern,
 * for one model. The validator prefixes each model error with
 * `model '<key>': ` and names the field as `'options.<f>'`,
 * `'options.specProfile.<f>'`, or `'displayName'`/`'hfRef'`/`'_comment'`. The
 * result keys are the option names, `specProfile.<f>`, the entry fields, or
 * `"general"` for entry-level / unknown-field messages that have no single
 * field to point at.
 */
export function fieldErrorsFor(errors: string[], modelKey: string): Record<string, string[]> {
  const out: Record<string, string[]> = {}
  const prefix = `model '${modelKey}': `
  for (const e of errors) {
    if (!e.startsWith(prefix)) continue
    const rest = e.slice(prefix.length)
    const spec = rest.match(/^'options\.specProfile\.(\w+)'/)
    const opt = rest.match(/^'options\.(\w+)'/)
    const entry = rest.match(/^'(\w+)'/)
    let field = "general"
    if (spec) field = `specProfile.${spec[1]}`
    else if (opt) field = opt[1]
    else if (entry && entry[1] !== "options") field = entry[1]
    ;(out[field] ??= []).push(rest)
  }
  return out
}

export const api = {
  getRegistry: () => request<{ registry: RegistryData | null; errors: string[] }>("/api/registry"),
  validate: (reg: RegistryData) =>
    request<{ errors: string[] }>("/api/validate", { method: "POST", ...json(reg) }),
  preview: (reg: RegistryData) =>
    request<{ ok: boolean; errors?: string[]; artifacts?: Artifacts }>("/api/preview", {
      method: "POST",
      ...json(reg),
    }),
  status: () => request<StatusResponse>("/api/status"),
  apply: (reg: RegistryData) =>
    request<{
      ok: boolean
      errors: string[]
      message?: string
      reloaded: boolean
      wrote: string[]
      busyLeases?: string[]
    }>("/api/apply", {
      method: "POST",
      ...json(reg),
    }),
  exportUrl: () => "/api/export",
  importRegistry: (content: string) =>
    request<{ ok: boolean; errors: string[]; wrote: string[] }>("/api/import", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: content,
    }),
  getJsonc: () => request<{ content: string | null }>("/api/opencode-jsonc"),
  putJsonc: (content: string) =>
    request<{ ok: boolean; wrote: string[] }>("/api/opencode-jsonc", {
      method: "PUT",
      headers: { "content-type": "text/plain" },
      body: content,
    }),
  getOpencodeJson: () => request<{ content: string | null }>("/api/opencode-json"),
}
