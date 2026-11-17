import { describe, expect, test } from "bun:test"
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs"
import { join } from "node:path"
import {
  fetchBackendStatus,
  readHeartbeat,
  readLeaseStatus,
  type LeaseStatus,
} from "./status.js"

function scratch(): string {
  return mkdtempSync("/tmp/opencode/status-")
}

describe("readHeartbeat", () => {
  test("reports the age of a present heartbeat", () => {
    const dir = scratch()
    try {
      const p = join(dir, "heartbeat.json")
      writeFileSync(p, JSON.stringify({ at: 1000, pid: 42, instanceId: "42.abc" }))
      const hb = readHeartbeat(p, 5000)
      expect(hb.present).toBe(true)
      expect(hb.at).toBe(1000)
      expect(hb.ageMs).toBe(4000)
      expect(hb.pid).toBe(42)
      expect(hb.instanceId).toBe("42.abc")
    } finally {
      rmSync(dir, { recursive: true, force: true })
    }
  })

  test("reports absent when the file is missing", () => {
    const dir = scratch()
    try {
      const hb = readHeartbeat(join(dir, "nope.json"), 5000)
      expect(hb.present).toBe(false)
    } finally {
      rmSync(dir, { recursive: true, force: true })
    }
  })

  test("reports present but no age when the file is unreadable", () => {
    const dir = scratch()
    try {
      const p = join(dir, "heartbeat.json")
      writeFileSync(p, "not json")
      const hb = readHeartbeat(p, 5000)
      expect(hb.present).toBe(true)
      expect(hb.ageMs).toBeNull()
    } finally {
      rmSync(dir, { recursive: true, force: true })
    }
  })
})

describe("readLeaseStatus", () => {
  function writeLease(dir: string, name: string, lease: Record<string, unknown>): void {
    writeFileSync(join(dir, name), JSON.stringify(lease))
  }

  test("flags a live busy lease", () => {
    const dir = scratch()
    try {
      mkdirSync(dir, { recursive: true })
      writeLease(dir, "1.aa.json", { instanceId: "1.aa", pid: 1, bootId: "b", busySince: 100 })
      writeLease(dir, "2.bb.json", { instanceId: "2.bb", pid: 2, bootId: "b", busySince: null })
      const alive = (pid: number) => pid === 1 || pid === 2
      const st = readLeaseStatus(dir, alive)
      expect(st.readable).toBe(true)
      expect(st.busy).toBe(true)
      expect(st.busyLeases.map((l) => l.instanceId)).toEqual(["1.aa"])
    } finally {
      rmSync(dir, { recursive: true, force: true })
    }
  })

  test("does not flag a busy lease whose process is dead", () => {
    const dir = scratch()
    try {
      mkdirSync(dir, { recursive: true })
      writeLease(dir, "1.aa.json", { instanceId: "1.aa", pid: 1, bootId: "b", busySince: 100 })
      const st = readLeaseStatus(dir, () => false)
      expect(st.busy).toBe(false)
      expect(st.busyLeases).toEqual([])
    } finally {
      rmSync(dir, { recursive: true, force: true })
    }
  })

  test("reports an unreadable directory", () => {
    const st = readLeaseStatus("/tmp/opencode/does-not-exist-xyz", () => true)
    expect(st.readable).toBe(false)
    expect(st.error).toBeDefined()
  })

  test("reports an unreadable lease set when a lease is malformed", () => {
    const dir = scratch()
    try {
      mkdirSync(dir, { recursive: true })
      writeFileSync(join(dir, "bad.json"), "not json")
      const st = readLeaseStatus(dir, () => true)
      expect(st.readable).toBe(false)
      expect(st.error).toContain("bad.json")
    } finally {
      rmSync(dir, { recursive: true, force: true })
    }
  })

  test("ignores non-json files", () => {
    const dir = scratch()
    try {
      mkdirSync(dir, { recursive: true })
      writeFileSync(join(dir, "notes.txt"), "ignore me")
      const st = readLeaseStatus(dir, () => true)
      expect(st.readable).toBe(true)
      expect(st.leases).toEqual([])
    } finally {
      rmSync(dir, { recursive: true, force: true })
    }
  })
})

describe("fetchBackendStatus", () => {
  function fakeFetch(routes: Record<string, { status: number; body: unknown }>): typeof fetch {
    return (async (url: string) => {
      const route = routes[url]
      if (!route) return { ok: false, status: 404, json: async () => ({}), text: async () => "" }
      return {
        ok: route.status >= 200 && route.status < 300,
        status: route.status,
        json: async () => route.body,
        text: async () => JSON.stringify(route.body),
      }
    }) as typeof fetch
  }

  test("reports up with the resident model and version", async () => {
    const base = "http://127.0.0.1:8080"
    const fetchImpl = fakeFetch({
      [`${base}/health`]: { status: 200, body: "OK" },
      [`${base}/running`]: { status: 200, body: { running: [{ model: "qwen3-30b-a3b", state: "ready" }] } },
      [`${base}/api/version`]: { status: 200, body: { version: "0.9.1" } },
    })
    const st = await fetchBackendStatus(base, fetchImpl)
    expect(st.up).toBe(true)
    expect(st.running).toEqual([{ model: "qwen3-30b-a3b", state: "ready" }])
    expect(st.version).toBe("0.9.1")
  })

  test("reports down when the backend is unreachable", async () => {
    const fetchImpl = (async () => {
      throw new Error("ECONNREFUSED")
    }) as typeof fetch
    const st = await fetchBackendStatus("http://127.0.0.1:8080", fetchImpl)
    expect(st.up).toBe(false)
    expect(st.running).toEqual([])
    expect(st.version).toBeNull()
  })

  test("never calls /unload", async () => {
    const calls: string[] = []
    const fetchImpl = (async (url: string) => {
      calls.push(url)
      return { ok: true, status: 200, json: async () => ({}), text: async () => "" }
    }) as typeof fetch
    await fetchBackendStatus("http://127.0.0.1:8080", fetchImpl)
    expect(calls.some((c) => c.includes("/unload"))).toBe(false)
  })
})
