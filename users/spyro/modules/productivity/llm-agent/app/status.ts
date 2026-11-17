/**
 * Read-only status: the llama-swap backend, the unload-policy heartbeat, and
 * the lease set.
 *
 * Everything here is read-only and safe to poll. In particular the backend
 * probe calls ONLY `/health`, `/running`, and `/api/version` — never `/unload`,
 * which would evict every running model (settled by #90). The heartbeat's *age*
 * is surfaced, not just its presence, because the unload-policy plugin can fail
 * to load and leave a stale heartbeat behind.
 */
import { readdirSync, readFileSync } from "node:fs"
import { join } from "node:path"

// --- heartbeat ---------------------------------------------------------------

/** The unload-policy heartbeat, with its age relative to `now`. */
export interface Heartbeat {
  present: boolean
  /** Epoch ms the plugin last wrote the heartbeat. */
  at?: number
  /** `now - at`, or `null` when the heartbeat is present but has no usable `at`. */
  ageMs: number | null
  pid?: number
  instanceId?: string
}

export function readHeartbeat(path: string, now: number): Heartbeat {
  let text: string
  try {
    text = readFileSync(path, "utf8")
  } catch {
    return { present: false, ageMs: null }
  }
  try {
    const parsed = JSON.parse(text) as { at?: unknown; pid?: unknown; instanceId?: unknown }
    const at = typeof parsed.at === "number" ? parsed.at : null
    return {
      present: true,
      ...(at !== null ? { at } : {}),
      ageMs: at !== null ? now - at : null,
      ...(typeof parsed.pid === "number" ? { pid: parsed.pid } : {}),
      ...(typeof parsed.instanceId === "string" ? { instanceId: parsed.instanceId } : {}),
    }
  } catch {
    // Present on disk but not valid JSON: report it, with no age.
    return { present: true, ageMs: null }
  }
}

// --- lease set ---------------------------------------------------------------

/** One lease, as the busy-lease check needs it. */
export interface LeaseInfo {
  instanceId: string
  pid: number
  alive: boolean
  busySince: number | null
  lastLocalActivityAt: number | null
}

/** The lease set as read, including the failure to read it. */
export interface LeaseStatus {
  readable: boolean
  error?: string
  leases: LeaseInfo[]
  /** True when a live lease reports a busy session. */
  busy: boolean
  /** The live, busy leases, for a concrete "who is busy" message. */
  busyLeases: LeaseInfo[]
}

/**
 * Read the lease directory and report whether a live lease is busy. The
 * liveness predicate is injected so the test can decide which pids are alive
 * without touching the real process table.
 */
export function readLeaseStatus(
  dir: string,
  isAlive: (pid: number, bootId: string | null) => boolean,
): LeaseStatus {
  let names: string[]
  try {
    names = readdirSync(dir)
  } catch (error) {
    return {
      readable: false,
      error: `lease directory unreadable: ${String(error)}`,
      leases: [],
      busy: false,
      busyLeases: [],
    }
  }
  const leases: LeaseInfo[] = []
  for (const name of names) {
    if (!name.endsWith(".json")) continue
    let parsed: Record<string, unknown>
    try {
      parsed = JSON.parse(readFileSync(join(dir, name), "utf8")) as Record<string, unknown>
    } catch (error) {
      // A lease that cannot be parsed is not a dead lease; it makes the set
      // unreadable, and an unreadable set does not permit an unload.
      return {
        readable: false,
        error: `lease '${name}' unreadable: ${String(error)}`,
        leases: [],
        busy: false,
        busyLeases: [],
      }
    }
    const pid = Number(parsed.pid ?? -1)
    const bootId = (parsed.bootId as string | undefined) ?? null
    leases.push({
      instanceId: String(parsed.instanceId ?? name),
      pid,
      alive: isAlive(pid, bootId),
      busySince: (parsed.busySince as number | null) ?? null,
      lastLocalActivityAt: (parsed.lastLocalActivityAt as number | null) ?? null,
    })
  }
  const busyLeases = leases.filter((l) => l.alive && l.busySince !== null)
  return { readable: true, leases, busy: busyLeases.length > 0, busyLeases }
}

// --- liveness (ported from the unload-policy plugin) -------------------------

let cachedBootId: string | null | undefined

/** The kernel boot id; a lease from before the last boot is not trustworthy. */
export function currentBootId(): string | null {
  if (cachedBootId !== undefined) return cachedBootId
  try {
    cachedBootId = readFileSync("/proc/sys/kernel/random/boot_id", "utf8").trim()
  } catch {
    cachedBootId = null
  }
  return cachedBootId
}

/**
 * Whether the process that wrote a lease still exists. A recycled pid belongs
 * to somebody else, so the boot id has to agree too. Ported from the plugin.
 */
export function isProcessAlive(pid: number, bootId: string | null): boolean {
  if (!Number.isInteger(pid) || pid <= 0) return false
  const current = currentBootId()
  if (current !== null && bootId !== current) return false
  try {
    process.kill(pid, 0)
    return true
  } catch (error) {
    // EPERM means the process exists but belongs to another user.
    return (error as { code?: string }).code === "EPERM"
  }
}

// --- backend -----------------------------------------------------------------

/** A model the backend reports as resident. */
export interface RunningModel {
  model: string
  state: string
}

/** The llama-swap backend status, from the safe-to-poll endpoints only. */
export interface BackendStatus {
  up: boolean
  running: RunningModel[]
  version: string | null
}

/**
 * Poll the backend's safe endpoints: `/health` (liveness), `/running` (the
 * resident model), and `/api/version`. `fetchImpl` is injected so the test can
 * substitute a fake. Never calls `/unload`.
 */
export async function fetchBackendStatus(
  base: string,
  fetchImpl: typeof fetch,
): Promise<BackendStatus> {
  let up = false
  try {
    const res = await fetchImpl(`${base}/health`)
    up = res.ok
  } catch {
    up = false
  }

  let running: RunningModel[] = []
  try {
    const res = await fetchImpl(`${base}/running`)
    if (res.ok) {
      const data = (await res.json()) as { running?: Array<{ model?: unknown; state?: unknown }> }
      running = (data.running ?? []).map((r) => ({
        model: typeof r.model === "string" ? r.model : String(r.model ?? ""),
        state: typeof r.state === "string" ? r.state : String(r.state ?? ""),
      }))
    }
  } catch {
    running = []
  }

  let version: string | null = null
  try {
    const res = await fetchImpl(`${base}/api/version`)
    if (res.ok) {
      const data = (await res.json()) as { version?: unknown }
      version = typeof data.version === "string" ? data.version : null
    }
  } catch {
    version = null
  }

  return { up, running, version }
}
