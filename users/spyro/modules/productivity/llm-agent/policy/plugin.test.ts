import { afterEach, beforeEach, describe, expect, test } from "bun:test"
import { mkdtempSync, readdirSync, readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import plugin, { createUnloadPolicy } from "./plugin.js"

const SINGLETON = Symbol.for("llm-agent.unload-policy.singleton")
const CONFIG = {
  idleThresholdSeconds: 300,
  settleSeconds: 15,
  backend: "http://127.0.0.1:8080",
  localProviderId: "llama.cpp",
}

/** Counts POSTs to the unload endpoint without touching a real backend. */
let unloadCalls = 0
const realFetch = globalThis.fetch
globalThis.fetch = (async (url: string) => {
  if (String(url).endsWith("/api/models/unload")) {
    unloadCalls += 1
    return { ok: true, status: 200 }
  }
  return realFetch(url)
}) as typeof fetch

let root: string

function policyPath(): string {
  return join(root, ".config", "llama-swap", "unload-policy.json")
}

function leases(): string[] {
  const dir = join(root, ".local", "state", "llm-agent", "leases")
  if (!existsSync(dir)) return []
  return readdirSync(dir).filter((n) => n.endsWith(".json")).sort()
}

function readLease(name: string): Record<string, number | string | null> {
  return JSON.parse(
    readFileSync(join(root, ".local", "state", "llm-agent", "leases", name), "utf8"),
  ) as Record<string, number | string | null>
}

function heartbeat(): Record<string, number | string> {
  return JSON.parse(
    readFileSync(join(root, ".local", "state", "llm-agent", "heartbeat.json"), "utf8"),
  ) as Record<string, number | string>
}

function policyLog(): string {
  const path = join(root, ".local", "state", "llm-agent", "policy.log")
  return existsSync(path) ? readFileSync(path, "utf8") : ""
}

/** A v2 event, as the policy reads it: the payload is under `data`. */
function statusEvent(sessionID: string, type: string) {
  return { type: "session.status", data: { sessionID, status: { type } } }
}

/**
 * A controllable stand-in for the v2 plugin context: an event stream the test
 * can push into, and a `context` hook that captures its callback.
 */
function makeCtx() {
  const queue: unknown[] = []
  let resolver: (() => void) | null = null
  let ended = false
  let contextCallback: ((input: { sessionID: string; model?: { providerID?: string; id?: string } }) => void) | undefined
  const hookDisposes: number[] = []
  let hookCalls = 0

  return {
    push(event: unknown) {
      queue.push(event)
      if (resolver) {
        const r = resolver
        resolver = null
        r()
      }
    },
    end() {
      ended = true
      if (resolver) {
        const r = resolver
        resolver = null
        r()
      }
    },
    ctx: {
      event: {
        subscribe: (_options?: unknown) =>
          (async function* () {
            for (;;) {
              while (queue.length > 0) yield queue.shift()
              if (ended) return
              await new Promise<void>((r) => {
                resolver = r
              })
            }
          })(),
      },
      session: {
        hook: async (_name: string, callback: (input: { sessionID: string; model?: { providerID?: string; id?: string } }) => void) => {
          contextCallback = callback
          const id = hookCalls++
          hookDisposes.push(id)
          return {
            dispose: async () => {
              // Mark this registration disposed; the test asserts via hookDisposes.
              hookDisposes[hookDisposes.length - 1] = -1
            },
          }
        },
      },
    },
    context(input: { sessionID: string; model?: { providerID?: string; id?: string } }) {
      contextCallback?.(input)
    },
    hookDisposed(): boolean {
      return hookDisposes.length > 0 && hookDisposes.every((d) => d === -1)
    },
  }
}

beforeEach(() => {
  root = mkdtempSync(join(tmpdir(), "llm-agent-policy-"))
  process.env.HOME = root
  delete process.env.XDG_STATE_HOME
  mkdirSync(join(root, ".config", "llama-swap"), { recursive: true })
  writeFileSync(policyPath(), JSON.stringify(CONFIG))
  unloadCalls = 0
  delete (globalThis as Record<symbol, unknown>)[SINGLETON]
})

afterEach(() => {
  delete (globalThis as Record<symbol, unknown>)[SINGLETON]
})

describe("plugin setup (the v2 wiring)", () => {
  test("writes a heartbeat and a lease when a location loads", async () => {
    const { ctx } = makeCtx()
    const cleanup = await plugin.setup!(ctx as never)
    const beat = heartbeat()
    expect(typeof beat.at).toBe("number")
    expect(beat.pid).toBe(process.pid)
    expect(leases().length).toBe(1)
    await cleanup()
  })

  test("reports the policy as loaded, so absence of a heartbeat means something", async () => {
    const { ctx } = makeCtx()
    const cleanup = await plugin.setup!(ctx as never)
    expect(policyLog().includes("unload policy loaded")).toBe(true)
    await cleanup()
  })

  test("two locations in one process share one lease", async () => {
    const a = makeCtx()
    const b = makeCtx()
    const cleanupA = await plugin.setup!(a.ctx as never)
    const cleanupB = await plugin.setup!(b.ctx as never)
    // One process, one lease. Two would each look like a separate instance.
    expect(leases().length).toBe(1)
    await cleanupA()
    // The first location leaving does not tear down: a sibling is still here.
    expect(leases().length).toBe(1)
    await cleanupB()
    expect(leases().length).toBe(0)
  })

  test("a location's events and model selections reach the shared policy", async () => {
    const { ctx, push, context } = makeCtx()
    const cleanup = await plugin.setup!(ctx as never)

    context({ sessionID: "s1", model: { providerID: "llama.cpp", id: "gpt-oss-20b" } })
    push(statusEvent("s1", "busy"))
    // The event stream is consumed asynchronously; give the loop a turn.
    await new Promise((r) => {
      setTimeout(() => r(undefined), 20)
    })

    const lease = readLease(leases()[0])
    expect(typeof lease.lastLocalActivityAt).toBe("number")
    expect(typeof lease.busySince).toBe("number")
    await cleanup()
  })

  test("does nothing and says so when the generated thresholds are missing", async () => {
    // The policy config is read from $HOME, not from the plugin's working
    // directory, so a fresh HOME with no generated config is the real case.
    const bare = mkdtempSync(join(tmpdir(), "llm-agent-bare-"))
    const previous = process.env.HOME
    process.env.HOME = bare
    try {
      const { ctx } = makeCtx()
      const cleanup = await plugin.setup!(ctx as never)
      expect(existsSync(join(bare, ".local", "state", "llm-agent", "heartbeat.json"))).toBe(false)
      expect(
        readFileSync(join(bare, ".local", "state", "llm-agent", "policy.log"), "utf8").includes(
          "unload policy disabled",
        ),
      ).toBe(true)
      // A no-op cleanup: nothing to tear down.
      await cleanup()
    } finally {
      process.env.HOME = previous
    }
  })
})

describe("session status", () => {
  test("a busy session publishes busySince and clears idleSince", async () => {
    const policy = createUnloadPolicy(CONFIG, "t1")
    policy.addLocation()
    policy.onEvent(statusEvent("s1", "busy"))
    const lease = readLease("t1.json")
    expect(typeof lease.busySince).toBe("number")
    expect(lease.idleSince).toBe(null)
    await policy.dispose()
  })

  test("publishing idle twice for one turn does not restart the idle clock", async () => {
    let clock = 1_000_000
    const policy = createUnloadPolicy(CONFIG, "dup", () => clock)
    policy.addLocation()
    const status = (type: string) => policy.onEvent(statusEvent("s1", type))

    status("busy")
    status("idle")
    const first = readLease("dup.json").idleSince

    // A failed or cancelled turn can report idle again. If this moved the clock
    // the resident model would be held for a whole extra threshold.
    clock += 5_000
    status("idle")
    expect(readLease("dup.json").idleSince).toBe(first)

    await policy.dispose()
  })

  test("a later turn starts a new idle epoch", async () => {
    let clock = 1_000_000
    const policy = createUnloadPolicy(CONFIG, "epoch", () => clock)
    policy.addLocation()
    const status = (type: string) => policy.onEvent(statusEvent("s1", type))

    status("busy")
    status("idle")
    const first = readLease("epoch.json").idleSince

    clock += 60_000
    status("busy")
    status("idle")
    expect(readLease("epoch.json").idleSince === first).toBe(false)
    await policy.dispose()
  })

  test("one busy session keeps the lease busy while a sibling session is idle", async () => {
    const policy = createUnloadPolicy(CONFIG, "sib")
    policy.addLocation()
    const status = (id: string, type: string) => policy.onEvent(statusEvent(id, type))

    status("a", "idle")
    status("b", "busy")
    const lease = readLease("sib.json")
    expect(typeof lease.busySince).toBe("number")
    expect(lease.idleSince).toBe(null)

    status("b", "idle")
    expect(readLease("sib.json").idleSince !== null).toBe(true)
    await policy.dispose()
  })
})

describe("model selection", () => {
  test("a local session records local activity", async () => {
    const policy = createUnloadPolicy(CONFIG, "loc")
    policy.addLocation()
    policy.onContext("s1", { providerID: "llama.cpp", id: "gpt-oss-20b" })
    const lease = readLease("loc.json")
    expect(typeof lease.lastLocalActivityAt).toBe("number")
    await policy.dispose()
  })

  test("a cloud session leaves local activity untouched on selection", async () => {
    // Cloud work must not hold the resident model resident for the length of a
    // conversation that never used it.
    const policy = createUnloadPolicy(CONFIG, "cloud")
    policy.addLocation()
    policy.onContext("s1", { providerID: "opencode", id: "big-pickle" })
    expect(readLease("cloud.json").lastLocalActivityAt).toBe(null)
    await policy.dispose()
  })

  test("a cloud session going busy does not refresh local activity", async () => {
    // Both guards have to hold: the model-selection path and the status path.
    // This stops the lease being *refreshed*. Note that a busy session still
    // blocks an unload outright via `lease-busy`; releasing on a cloud switch
    // while the session stays open is #51's work, not this ticket's.
    const policy = createUnloadPolicy(CONFIG, "cloud2")
    policy.addLocation()
    policy.onContext("s1", { providerID: "opencode", id: "big-pickle" })
    policy.onEvent(statusEvent("s1", "busy"))
    expect(readLease("cloud2.json").lastLocalActivityAt).toBe(null)
    expect(typeof readLease("cloud2.json").busySince).toBe("number")
    await policy.dispose()
  })

  test("streaming deltas against a local session refresh local activity", async () => {
    // Deltas arrive many times a second, so they move the in-memory timestamp
    // and the next publish carries it. That is safe: while a generation is
    // running, busySince is what blocks a peer, and it was published on the
    // transition into busy.
    let clock = 1_000_000
    const policy = createUnloadPolicy(CONFIG, "delta", () => clock)
    policy.addLocation()
    policy.onContext("s1", { providerID: "llama.cpp", id: "gpt-oss-20b" })
    const before = readLease("delta.json").lastLocalActivityAt

    clock += 30_000
    policy.onEvent({ type: "session.text.delta", data: { sessionID: "s1" } })
    // Publishing via a status change that does *not* itself touch local
    // activity, so the timestamp can only have come from the delta above.
    policy.onEvent(statusEvent("s1", "idle"))

    expect(readLease("delta.json").lastLocalActivityAt).toBe(clock)
    expect(readLease("delta.json").lastLocalActivityAt === before).toBe(false)
    await policy.dispose()
  })
})

describe("the unload path", () => {
  /** Drives a session from busy to idle, then far enough past the threshold. */
  async function idleLocalSession(policy: ReturnType<typeof createUnloadPolicy>, clock: { now: number }): Promise<void> {
    policy.onContext("s1", { providerID: "llama.cpp", id: "gpt-oss-20b" })
    policy.onEvent(statusEvent("s1", "busy"))
    clock.now += 10_000
    policy.onEvent(statusEvent("s1", "idle"))
    clock.now += 400_000
  }

  test("does not unload while the session is mid-generation", async () => {
    const clock = { now: 1_000_000 }
    const policy = createUnloadPolicy(CONFIG, "busy", () => clock.now)
    policy.addLocation()
    policy.onContext("s1", { providerID: "llama.cpp", id: "gpt-oss-20b" })
    policy.onEvent(statusEvent("s1", "busy"))
    // Far past the threshold, but still generating.
    clock.now += 400_000
    const result = await policy.tick()
    expect(result.decision).toEqual({ unload: false, reason: "lease-busy" })
    expect(unloadCalls).toBe(0)
    await policy.dispose()
  })

  test("unloads once a session has been idle past the threshold", async () => {
    const clock = { now: 1_000_000 }
    const policy = createUnloadPolicy(CONFIG, "idle", () => clock.now)
    policy.addLocation()
    await idleLocalSession(policy, clock)
    const result = await policy.tick()
    expect(result.decision.unload).toBe(true)
    expect(result.attempted).toBe(true)
    expect(unloadCalls).toBe(1)
    await policy.dispose()
  })

  test("repeated idle publications for one turn still produce one attempt", async () => {
    // The acceptance criterion in full: a failed or cancelled turn reports idle
    // more than once, and the timer fires repeatedly on top of that.
    const clock = { now: 1_000_000 }
    const policy = createUnloadPolicy(CONFIG, "dup2", () => clock.now)
    policy.addLocation()
    await idleLocalSession(policy, clock)

    await policy.tick()
    for (let i = 0; i < 5; i++) {
      clock.now += 5_000
      policy.onEvent(statusEvent("s1", "idle"))
      await policy.tick()
    }
    expect(unloadCalls).toBe(1)
    await policy.dispose()
  })

  test("a new turn after an unload earns a fresh attempt", async () => {
    const clock = { now: 1_000_000 }
    const policy = createUnloadPolicy(CONFIG, "again", () => clock.now)
    policy.addLocation()
    await idleLocalSession(policy, clock)
    await policy.tick()
    expect(unloadCalls).toBe(1)

    clock.now += 60_000
    policy.onContext("s1", { providerID: "llama.cpp", id: "gpt-oss-20b" })
    await idleLocalSession(policy, clock)
    await policy.tick()
    expect(unloadCalls).toBe(2)
    await policy.dispose()
  })

  test("the settle delay refuses the first evaluation after a turn ends", async () => {
    const clock = { now: 1_000_000 }
    const policy = createUnloadPolicy(CONFIG, "settle", () => clock.now)
    policy.addLocation()
    policy.onContext("s1", { providerID: "llama.cpp", id: "gpt-oss-20b" })
    policy.onEvent(statusEvent("s1", "busy"))
    clock.now += 400_000 // idle, but long past the threshold
    policy.onEvent(statusEvent("s1", "idle"))

    const first = await policy.tick()
    expect(first.decision).toEqual({ unload: false, reason: "lease-settling" })
    expect(unloadCalls).toBe(0)

    clock.now += CONFIG.settleSeconds * 1000
    const second = await policy.tick()
    expect(second.decision.unload).toBe(true)
    expect(unloadCalls).toBe(1)
    await policy.dispose()
  })

  test("a corrupt sibling lease is an unreadable set, not a dead one", async () => {
    // The dangerous case is not a missing directory but a sibling's lease that
    // cannot be parsed: treating it as absent would let one instance's bad
    // write authorise unloading under another instance's feet.
    const clock = { now: 1_000_000 }
    const policy = createUnloadPolicy(CONFIG, "corrupt", () => clock.now)
    policy.addLocation()
    await idleLocalSession(policy, clock)
    writeFileSync(join(root, ".local", "state", "llm-agent", "leases", "9999.zzz.json"), "{not json")

    const result = await policy.tick()
    expect(result.decision).toEqual({ unload: false, reason: "lease-set-unreadable" })
    expect(unloadCalls).toBe(0)
    await policy.dispose()
  })

  test("a lease claiming a busy sibling that no longer exists does not block", async () => {
    const clock = { now: 1_000_000 }
    const policy = createUnloadPolicy(CONFIG, "ghost", () => clock.now)
    policy.addLocation()
    await idleLocalSession(policy, clock)
    writeFileSync(
      join(root, ".local", "state", "llm-agent", "leases", "9999.ghost.json"),
      JSON.stringify({ instanceId: "9999.ghost", pid: 999999, startedAt: clock.now - 900_000, lastLocalActivityAt: clock.now, busySince: clock.now, idleSince: null }),
    )

    const result = await policy.tick()
    expect(result.decision.unload).toBe(true)
    await policy.dispose()
  })
})

describe("dispose and location teardown", () => {
  test("removes the lease so the next instance does not read a stale one", async () => {
    const policy = createUnloadPolicy(CONFIG, "test-instance")
    policy.addLocation()
    expect(leases()).toEqual(["test-instance.json"])
    await policy.dispose()
    expect(leases()).toEqual([])
  })

  test("unloads when the exiting instance is the last live one", async () => {
    const clock = { now: 1_000_000 }
    const policy = createUnloadPolicy(CONFIG, "last-out", () => clock.now)
    policy.addLocation()
    policy.onContext("s1", { providerID: "llama.cpp", id: "gpt-oss-20b" })
    policy.onEvent(statusEvent("s1", "busy"))
    clock.now += 10_000
    policy.onEvent(statusEvent("s1", "idle"))
    clock.now += 400_000
    await policy.dispose()
    expect(unloadCalls).toBe(1)
    expect(leases()).toEqual([])
  })

  test("does not unload while a sibling instance is mid-generation", async () => {
    const clock = { now: 1_000_000 }
    const leaving = createUnloadPolicy(CONFIG, "leaving", () => clock.now)
    const staying = createUnloadPolicy(CONFIG, "staying", () => clock.now)
    leaving.addLocation()
    staying.addLocation()
    // The leaving instance goes idle past the threshold...
    leaving.onContext("s1", { providerID: "llama.cpp", id: "gpt-oss-20b" })
    leaving.onEvent(statusEvent("s1", "busy"))
    clock.now += 10_000
    leaving.onEvent(statusEvent("s1", "idle"))
    clock.now += 400_000
    // ...but the sibling is mid-generation on a local model.
    staying.onContext("s2", { providerID: "llama.cpp", id: "gpt-oss-20b" })
    staying.onEvent(statusEvent("s2", "busy"))

    await leaving.dispose()
    expect(unloadCalls).toBe(0)
    expect(leases()).toEqual(["staying.json"])

    // The sibling leaving last does unload.
    await staying.dispose()
    expect(unloadCalls).toBe(1)
  })

  test("removeLocation tears down only on the last location", async () => {
    const policy = createUnloadPolicy(CONFIG, "multi")
    policy.addLocation()
    policy.addLocation()
    expect(leases()).toEqual(["multi.json"])

    await policy.removeLocation()
    // One location remains: the lease is still published.
    expect(leases()).toEqual(["multi.json"])

    await policy.removeLocation()
    // The last location leaving removes the lease.
    expect(leases()).toEqual([])
  })
})
