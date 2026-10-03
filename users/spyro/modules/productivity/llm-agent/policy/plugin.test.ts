import { afterEach, beforeEach, describe, expect, test } from "bun:test"
import { mkdtempSync, readdirSync, readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { LlmAgentUnloadPolicy, createUnloadPolicy } from "./plugin.js"

const SINGLETON = Symbol.for("llm-agent.unload-policy.singleton")
const CONFIG = { idleThresholdSeconds: 300, settleSeconds: 15, backend: "http://127.0.0.1:8080" }

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
    const hooks = await LlmAgentUnloadPolicy({ client, directory: root })
    await hooks["chat.params"]!({ sessionID: "s1", model: { providerID: "opencode", id: "big-pickle" } })
    expect(readLease(leases()[0]).lastLocalActivityAt).toBe(null)
    await hooks.dispose!()
  })

  test("a cloud session going busy does not refresh local activity", async () => {
    // The cloud path and the busy path are separate guards, and both have to
    // hold: a busy cloud session must not hold the resident model either.
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

describe("dispose", () => {
  test("removes the lease so the next instance does not read a stale one", async () => {
    const hooks = createUnloadPolicy({ client, directory: root }, CONFIG, "test-instance")
    expect(leases()).toEqual(["test-instance.json"])
    await hooks.dispose!()
    expect(leases()).toEqual([])
  })
})
