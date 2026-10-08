import { afterEach, beforeEach, describe, expect, test } from "bun:test"
import { mkdtempSync, readdirSync, readFileSync, writeFileSync, mkdirSync, existsSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { LlmAgentUnloadPolicy, createUnloadPolicy } from "./plugin.js"

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
const logged: { level: string; message: string }[] = []

const client = {
  app: {
    log: ({ body }: { body: { level: string; message: string } }) => {
      logged.push({ level: body.level, message: body.message })
    },
  },
}

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

beforeEach(() => {
  root = mkdtempSync(join(tmpdir(), "llm-agent-policy-"))
  process.env.HOME = root
  delete process.env.XDG_STATE_HOME
  mkdirSync(join(root, ".config", "llama-swap"), { recursive: true })
  writeFileSync(policyPath(), JSON.stringify(CONFIG))
  logged.length = 0
  unloadCalls = 0
  delete (globalThis as Record<symbol, unknown>)[SINGLETON]
})

afterEach(() => {
  delete (globalThis as Record<symbol, unknown>)[SINGLETON]
})

describe("plugin load", () => {
  test("writes a heartbeat when it loads", async () => {
    await LlmAgentUnloadPolicy({ client, directory: root })
    const beat = heartbeat()
    expect(typeof beat.at).toBe("number")
    expect(beat.pid).toBe(process.pid)
  })

  test("publishes a lease identifying this process", async () => {
    await LlmAgentUnloadPolicy({ client, directory: root })
    expect(leases().length).toBe(1)
    const lease = readLease(leases()[0])
    expect(lease.pid).toBe(process.pid)
  })

  test("returns the same hooks when opencode calls the factory twice", async () => {
    const first = await LlmAgentUnloadPolicy({ client, directory: root })
    const second = await LlmAgentUnloadPolicy({ client, directory: root })
    expect(first).toBe(second)
    // One process, one lease. Two would each look like a separate instance.
    expect(leases().length).toBe(1)
  })

  test("reports the policy as loaded, so absence of a heartbeat means something", async () => {
    await LlmAgentUnloadPolicy({ client, directory: root })
    expect(logged.filter((l) => l.message === "unload policy loaded").length).toBe(1)
  })

  test("does nothing and says so when the generated thresholds are missing", async () => {
    // The policy config is read from $HOME, not from the plugin's working
    // directory, so a fresh HOME with no generated config is the real case.
    const bare = mkdtempSync(join(tmpdir(), "llm-agent-bare-"))
    const previous = process.env.HOME
    process.env.HOME = bare
    try {
      const hooks = await LlmAgentUnloadPolicy({ client, directory: bare })
      expect(hooks.event).toBe(undefined)
      expect(existsSync(join(bare, ".local", "state", "llm-agent", "heartbeat.json"))).toBe(false)
      expect(logged.some((l) => l.level === "error")).toBe(true)
    } finally {
      process.env.HOME = previous
    }
  })
})

describe("session status", () => {
  test("a busy session publishes busySince and clears idleSince", async () => {
    const hooks = await LlmAgentUnloadPolicy({ client, directory: root })
    await hooks.event!({
      event: { type: "session.status", properties: { sessionID: "s1", status: { type: "busy" } } },
    })
    const lease = readLease(leases()[0])
    expect(typeof lease.busySince).toBe("number")
    expect(lease.idleSince).toBe(null)
    await hooks.dispose!()
  })

  test("publishing idle twice for one turn does not restart the idle clock", async () => {
    let clock = 1_000_000
    const hooks = createUnloadPolicy({ client, directory: root }, CONFIG, "dup", () => clock)
    const status = (type: string) => hooks.event!({ event: { type: "session.status", properties: { sessionID: "s1", status: { type } } } })

    await status("busy")
    await status("idle")
    const first = readLease("dup.json").idleSince

    // A failed or cancelled turn can report idle again. If this moved the clock
    // the resident model would be held for a whole extra threshold.
    clock += 5_000
    await status("idle")
    expect(readLease("dup.json").idleSince).toBe(first)

    await hooks.dispose!()
  })

  test("a later turn starts a new idle epoch", async () => {
    let clock = 1_000_000
    const hooks = createUnloadPolicy({ client, directory: root }, CONFIG, "epoch", () => clock)
    const status = async (type: string) => {
      await hooks.event!({ event: { type: "session.status", properties: { sessionID: "s1", status: { type } } } })
    }

    await status("busy")
    await status("idle")
    const first = readLease("epoch.json").idleSince

    clock += 60_000
    await status("busy")
    await status("idle")
    expect(readLease("epoch.json").idleSince === first).toBe(false)
    await hooks.dispose!()
  })

  test("one busy session keeps the lease busy while a sibling session is idle", async () => {
    const hooks = await LlmAgentUnloadPolicy({ client, directory: root })
    const status = (id: string, type: string) =>
      hooks.event!({ event: { type: "session.status", properties: { sessionID: id, status: { type } } } })

    await status("a", "idle")
    await status("b", "busy")
    const lease = readLease(leases()[0])
    expect(typeof lease.busySince).toBe("number")
    expect(lease.idleSince).toBe(null)

    await status("b", "idle")
    expect(readLease(leases()[0]).idleSince !== null).toBe(true)
    await hooks.dispose!()
  })
})

describe("model selection", () => {
  test("a local session records local activity", async () => {
    const hooks = await LlmAgentUnloadPolicy({ client, directory: root })
    await hooks["chat.params"]!({ sessionID: "s1", model: { providerID: "llama.cpp", id: "gpt-oss-20b" } })
    const lease = readLease(leases()[0])
    expect(typeof lease.lastLocalActivityAt).toBe("number")
    await hooks.dispose!()
  })

  test("a cloud session leaves local activity untouched on selection", async () => {
    // Cloud work must not hold the resident model resident for the length of a
    // conversation that never used it.
    const hooks = await LlmAgentUnloadPolicy({ client, directory: root })
    await hooks["chat.params"]!({ sessionID: "s1", model: { providerID: "opencode", id: "big-pickle" } })
    expect(readLease(leases()[0]).lastLocalActivityAt).toBe(null)
    await hooks.dispose!()
  })

  test("a cloud session going busy does not refresh local activity", async () => {
    // Both guards have to hold: the model-selection path and the status path.
    // This stops the lease being *refreshed*. Note that a busy session still
    // blocks an unload outright via `lease-busy`; releasing on a cloud switch
    // while the session stays open is #51's work, not this ticket's.
    const hooks = await LlmAgentUnloadPolicy({ client, directory: root })
    await hooks["chat.params"]!({ sessionID: "s1", model: { providerID: "opencode", id: "big-pickle" } })
    await hooks.event!({
      event: { type: "session.status", properties: { sessionID: "s1", status: { type: "busy" } } },
    })
    expect(readLease(leases()[0]).lastLocalActivityAt).toBe(null)
    expect(typeof readLease(leases()[0]).busySince).toBe("number")
    await hooks.dispose!()
  })

  test("streaming parts against a local session refresh local activity", async () => {
    // Deltas arrive many times a second, so they move the in-memory timestamp
    // and the next publish carries it. That is safe: while a generation is
    // running, busySince is what blocks a peer, and it was published on the
    // transition into busy.
    let clock = 1_000_000
    const hooks = createUnloadPolicy({ client, directory: root }, CONFIG, "delta", () => clock)
    await hooks["chat.params"]!({ sessionID: "s1", model: { providerID: "llama.cpp", id: "gpt-oss-20b" } })
    const before = readLease("delta.json").lastLocalActivityAt

    clock += 30_000
    await hooks.event!({ event: { type: "message.part.delta", properties: { sessionID: "s1" } } })
    // Publishing via a status change that does *not* itself touch local
    // activity, so the timestamp can only have come from the delta above.
    await hooks.event!({
      event: { type: "session.status", properties: { sessionID: "s1", status: { type: "idle" } } },
    })

    expect(readLease("delta.json").lastLocalActivityAt).toBe(clock)
    expect(readLease("delta.json").lastLocalActivityAt === before).toBe(false)
    await hooks.dispose!()
  })
})

describe("the unload path", () => {
  /** Drives a session from busy to idle, then far enough past the threshold. */
  async function idleLocalSession(hooks: any, clock: { now: number }): Promise<void> {
    await hooks["chat.params"]({ sessionID: "s1", model: { providerID: "llama.cpp", id: "gpt-oss-20b" } })
    await hooks.event({ event: { type: "session.status", properties: { sessionID: "s1", status: { type: "busy" } } } })
    clock.now += 10_000
    await hooks.event({ event: { type: "session.status", properties: { sessionID: "s1", status: { type: "idle" } } } })
    clock.now += 400_000
  }

  test("does not unload while the session is mid-generation", async () => {
    const clock = { now: 1_000_000 }
    const hooks = createUnloadPolicy({ client, directory: root }, CONFIG, "busy", () => clock.now) as any
    await hooks["chat.params"]({ sessionID: "s1", model: { providerID: "llama.cpp", id: "gpt-oss-20b" } })
    await hooks.event({ event: { type: "session.status", properties: { sessionID: "s1", status: { type: "busy" } } } })
    // Far past the threshold, but still generating.
    clock.now += 400_000
    const result = await hooks.__tick()
    expect(result.decision).toEqual({ unload: false, reason: "lease-busy" })
    expect(unloadCalls).toBe(0)
    await hooks.dispose()
  })

  test("unloads once a session has been idle past the threshold", async () => {
    const clock = { now: 1_000_000 }
    const hooks = createUnloadPolicy({ client, directory: root }, CONFIG, "idle", () => clock.now) as any
    await idleLocalSession(hooks, clock)
    const result = await hooks.__tick()
    expect(result.decision.unload).toBe(true)
    expect(result.attempted).toBe(true)
    expect(unloadCalls).toBe(1)
    await hooks.dispose()
  })

  test("repeated idle publications for one turn still produce one attempt", async () => {
    // The acceptance criterion in full: a failed or cancelled turn reports idle
    // more than once, and the timer fires repeatedly on top of that.
    const clock = { now: 1_000_000 }
    const hooks = createUnloadPolicy({ client, directory: root }, CONFIG, "dup2", () => clock.now) as any
    await idleLocalSession(hooks, clock)

    await hooks.__tick()
    for (let i = 0; i < 5; i++) {
      clock.now += 5_000
      await hooks.event({ event: { type: "session.status", properties: { sessionID: "s1", status: { type: "idle" } } } })
      await hooks.__tick()
    }
    expect(unloadCalls).toBe(1)
    await hooks.dispose()
  })

  test("a new turn after an unload earns a fresh attempt", async () => {
    const clock = { now: 1_000_000 }
    const hooks = createUnloadPolicy({ client, directory: root }, CONFIG, "again", () => clock.now) as any
    await idleLocalSession(hooks, clock)
    await hooks.__tick()
    expect(unloadCalls).toBe(1)

    clock.now += 60_000
    await hooks["chat.params"]({ sessionID: "s1", model: { providerID: "llama.cpp", id: "gpt-oss-20b" } })
    await idleLocalSession(hooks, clock)
    await hooks.__tick()
    expect(unloadCalls).toBe(2)
    await hooks.dispose()
  })

  test("the settle delay refuses the first evaluation after a turn ends", async () => {
    const clock = { now: 1_000_000 }
    const hooks = createUnloadPolicy({ client, directory: root }, CONFIG, "settle", () => clock.now) as any
    await hooks["chat.params"]({ sessionID: "s1", model: { providerID: "llama.cpp", id: "gpt-oss-20b" } })
    await hooks.event({ event: { type: "session.status", properties: { sessionID: "s1", status: { type: "busy" } } } })
    clock.now += 400_000 // idle, but long past the threshold
    await hooks.event({ event: { type: "session.status", properties: { sessionID: "s1", status: { type: "idle" } } } })

    const first = await hooks.__tick()
    expect(first.decision).toEqual({ unload: false, reason: "lease-settling" })
    expect(unloadCalls).toBe(0)

    clock.now += CONFIG.settleSeconds * 1000
    const second = await hooks.__tick()
    expect(second.decision.unload).toBe(true)
    expect(unloadCalls).toBe(1)
    await hooks.dispose()
  })

  test("a corrupt sibling lease is an unreadable set, not a dead one", async () => {
    // The dangerous case is not a missing directory but a sibling's lease that
    // cannot be parsed: treating it as absent would let one instance's bad
    // write authorise unloading under another instance's feet.
    const clock = { now: 1_000_000 }
    const hooks = createUnloadPolicy({ client, directory: root }, CONFIG, "corrupt", () => clock.now) as any
    await idleLocalSession(hooks, clock)
    writeFileSync(join(root, ".local", "state", "llm-agent", "leases", "9999.zzz.json"), "{not json")

    const result = await hooks.__tick()
    expect(result.decision).toEqual({ unload: false, reason: "lease-set-unreadable" })
    expect(unloadCalls).toBe(0)
    await hooks.dispose()
  })

  test("a lease claiming a busy sibling that no longer exists does not block", async () => {
    const clock = { now: 1_000_000 }
    const hooks = createUnloadPolicy({ client, directory: root }, CONFIG, "ghost", () => clock.now) as any
    await idleLocalSession(hooks, clock)
    writeFileSync(
      join(root, ".local", "state", "llm-agent", "leases", "9999.ghost.json"),
      JSON.stringify({ instanceId: "9999.ghost", pid: 999999, startedAt: clock.now - 900_000, lastLocalActivityAt: clock.now, busySince: clock.now, idleSince: null }),
    )

    const result = await hooks.__tick()
    expect(result.decision.unload).toBe(true)
    await hooks.dispose()
  })
})

describe("dispose", () => {
  test("removes the lease so the next instance does not read a stale one", async () => {
    const hooks = createUnloadPolicy({ client, directory: root }, CONFIG, "test-instance")
    expect(leases()).toEqual(["test-instance.json"])
    await hooks.dispose!()
    expect(leases()).toEqual([])
  })

  test("unloads when the exiting instance is the last live one", async () => {
    const clock = { now: 1_000_000 }
    const hooks = createUnloadPolicy({ client, directory: root }, CONFIG, "last-out", () => clock.now) as any
    await hooks["chat.params"]({ sessionID: "s1", model: { providerID: "llama.cpp", id: "gpt-oss-20b" } })
    await hooks.event({ event: { type: "session.status", properties: { sessionID: "s1", status: { type: "busy" } } } })
    clock.now += 10_000
    await hooks.event({ event: { type: "session.status", properties: { sessionID: "s1", status: { type: "idle" } } } })
    clock.now += 400_000
    await hooks.dispose()
    expect(unloadCalls).toBe(1)
    expect(leases()).toEqual([])
  })

  test("does not unload while a sibling instance is mid-generation", async () => {
    const clock = { now: 1_000_000 }
    const leaving = createUnloadPolicy({ client, directory: root }, CONFIG, "leaving", () => clock.now) as any
    const staying = createUnloadPolicy({ client, directory: root }, CONFIG, "staying", () => clock.now) as any
    // The leaving instance goes idle past the threshold...
    await leaving["chat.params"]({ sessionID: "s1", model: { providerID: "llama.cpp", id: "gpt-oss-20b" } })
    await leaving.event({ event: { type: "session.status", properties: { sessionID: "s1", status: { type: "busy" } } } })
    clock.now += 10_000
    await leaving.event({ event: { type: "session.status", properties: { sessionID: "s1", status: { type: "idle" } } } })
    clock.now += 400_000
    // ...but the sibling is mid-generation on a local model.
    await staying["chat.params"]({ sessionID: "s2", model: { providerID: "llama.cpp", id: "gpt-oss-20b" } })
    await staying.event({ event: { type: "session.status", properties: { sessionID: "s2", status: { type: "busy" } } } })

    await leaving.dispose()
    expect(unloadCalls).toBe(0)
    expect(leases()).toEqual(["staying.json"])

    // The sibling leaving last does unload.
    await staying.dispose()
    expect(unloadCalls).toBe(1)
  })
})
