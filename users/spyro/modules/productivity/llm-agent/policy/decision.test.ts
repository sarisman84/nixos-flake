import { describe, expect, test } from "bun:test"
import { isRepeatUnload, shouldUnload, type Lease, type LeaseSet, type Policy } from "./decision.js"

const NOW = 1_700_000_000_000
const POLICY: Policy = { idleThresholdMs: 300_000, settleMs: 15_000 }

function lease(over: Partial<Lease> = {}): Lease {
  return {
    instanceId: "a",
    pid: 100,
    alive: true,
    startedAt: NOW - 400_000,
    lastLocalActivityAt: NOW - 400_000,
    busySince: null,
    idleSince: NOW - 400_000,
    ...over,
  }
}

function readable(...leases: Lease[]): LeaseSet {
  return { readable: true, leases }
}

const UNREADABLE: LeaseSet = { readable: false, error: "EACCES" }

describe("shouldUnload", () => {
  test("unloads when the only local session has been idle past the threshold", () => {
    expect(shouldUnload(readable(lease()), [], NOW, POLICY)).toEqual({
      unload: true,
      reason: "all-leases-idle",
    })
  })

  test("holds the resident model while a local session is mid-generation", () => {
    const busy = lease({ busySince: NOW - 30_000, idleSince: null, lastLocalActivityAt: NOW })
    expect(shouldUnload(readable(busy), [], NOW, POLICY)).toEqual({
      unload: false,
      reason: "lease-busy",
    })
  })

  test("does not unload while the backend reports an entry in flight", () => {
    const idle = lease()
    const inflight = [{ id: "7", model: "gpt-oss-20b" }]
    expect(shouldUnload(readable(idle), inflight, NOW, POLICY)).toEqual({
      unload: false,
      reason: "inflight-present",
    })
  })

  test("releases for an idle cloud session, which never held a local model", () => {
    const cloud = lease({ lastLocalActivityAt: null, idleSince: NOW - 20_000 })
    expect(shouldUnload(readable(cloud), [], NOW, POLICY)).toEqual({
      unload: true,
      reason: "all-leases-idle",
    })
  })

  test("a live sibling that is busy blocks, even when this instance is long idle", () => {
    const me = lease({ instanceId: "me" })
    const sibling = lease({ instanceId: "sibling", pid: 200, busySince: NOW - 5_000, idleSince: null })
    expect(shouldUnload(readable(me, sibling), [], NOW, POLICY)).toEqual({
      unload: false,
      reason: "lease-busy",
    })
  })

  test("a dead process does not block, however recently it was busy", () => {
    const me = lease({ instanceId: "me" })
    const corpse = lease({
      instanceId: "corpse",
      pid: 200,
      alive: false,
      busySince: NOW - 1_000,
      idleSince: null,
    })
    expect(shouldUnload(readable(me, corpse), [], NOW, POLICY)).toEqual({
      unload: true,
      reason: "all-leases-idle",
    })
  })

  test("an unreadable lease set refuses: unavailability is not permission", () => {
    expect(shouldUnload(UNREADABLE, [], NOW, POLICY)).toEqual({
      unload: false,
      reason: "lease-set-unreadable",
    })
  })

  test("an unreadable lease set refuses even when nothing else objects", () => {
    expect(shouldUnload(UNREADABLE, [], NOW, POLICY).unload).toBe(false)
  })

  test("a readable set with no live lease refuses rather than assuming nobody is there", () => {
    const corpse = lease({ alive: false })
    expect(shouldUnload(readable(corpse), [], NOW, POLICY)).toEqual({
      unload: false,
      reason: "no-live-lease",
    })
  })

  test("recent local activity holds the model even while the session reads idle", () => {
    const recent = lease({ lastLocalActivityAt: NOW - 299_000 })
    expect(shouldUnload(readable(recent), [], NOW, POLICY)).toEqual({
      unload: false,
      reason: "lease-active",
    })
  })

  test("the settle delay covers a session that reads idle before it is marked busy", () => {
    // A turn has just been submitted: the lease still says idle, but the idle
    // observation is younger than the settle delay, so it has not stood still
    // long enough to be believed.
    const starting = lease({ lastLocalActivityAt: NOW - 400_000, idleSince: NOW - 2_000 })
    expect(shouldUnload(readable(starting), [], NOW, POLICY)).toEqual({
      unload: false,
      reason: "lease-settling",
    })
  })

  test("an idle observation exactly at the settle boundary is believed", () => {
    const settled = lease({ idleSince: NOW - POLICY.settleMs })
    expect(shouldUnload(readable(settled), [], NOW, POLICY)).toEqual({
      unload: true,
      reason: "all-leases-idle",
    })
  })

  test("an idle observation one millisecond inside the settle boundary is not", () => {
    const settling = lease({ idleSince: NOW - POLICY.settleMs + 1 })
    expect(shouldUnload(readable(settling), [], NOW, POLICY)).toEqual({
      unload: false,
      reason: "lease-settling",
    })
  })

  test("local activity exactly at the threshold boundary releases", () => {
    const boundary = lease({ lastLocalActivityAt: NOW - POLICY.idleThresholdMs })
    expect(shouldUnload(readable(boundary), [], NOW, POLICY)).toEqual({
      unload: true,
      reason: "all-leases-idle",
    })
  })

  test("local activity one millisecond inside the threshold is still held", () => {
    const held = lease({ lastLocalActivityAt: NOW - POLICY.idleThresholdMs + 1 })
    expect(shouldUnload(readable(held), [], NOW, POLICY)).toEqual({
      unload: false,
      reason: "lease-active",
    })
  })

  test("an instance that has just started and seen no session does not authorise an unload", () => {
    const justStarted = lease({ startedAt: NOW - 1_000, busySince: null, idleSince: null, lastLocalActivityAt: null })
    expect(shouldUnload(readable(justStarted), [], NOW, POLICY)).toEqual({
      unload: false,
      reason: "lease-unobserved",
    })
  })

  test("a long-lived instance with no sessions is an idle editor, not a veto", () => {
    // Otherwise one open instance with no session in it would pin the resident
    // model for as long as it stayed open — the failure this policy removes.
    const idleEditor = lease({ busySince: null, idleSince: null, lastLocalActivityAt: null })
    expect(shouldUnload(readable(idleEditor), [], NOW, POLICY)).toEqual({
      unload: true,
      reason: "all-leases-idle",
    })
  })

  test("the unobserved veto expires exactly at the settle boundary", () => {
    const atBoundary = lease({ startedAt: NOW - POLICY.settleMs, busySince: null, idleSince: null })
    expect(shouldUnload(readable(atBoundary), [], NOW, POLICY).unload).toBe(true)
    const inside = lease({ startedAt: NOW - POLICY.settleMs + 1, busySince: null, idleSince: null })
    expect(shouldUnload(readable(inside), [], NOW, POLICY).reason).toBe("lease-unobserved")
  })

  test("every reason is a non-empty string, so a no-op can be logged", () => {
    const cases = [
      shouldUnload(readable(lease()), [], NOW, POLICY),
      shouldUnload(readable(lease({ busySince: NOW })), [], NOW, POLICY),
      shouldUnload(readable(lease()), [{ id: "1", model: null }], NOW, POLICY),
      shouldUnload(UNREADABLE, [], NOW, POLICY),
      shouldUnload(readable(lease({ idleSince: null, lastLocalActivityAt: null })), [], NOW, POLICY),
    ]
    for (const decision of cases) expect(decision.reason.length).toBeGreaterThan(0)
  })
})

describe("isRepeatUnload", () => {
  test("is a repeat when nothing has happened locally since the last unload", () => {
    const idle = lease()
    expect(isRepeatUnload(NOW - 30_000, readable(idle), NOW)).toBe(true)
  })

  test("is not a repeat once a lease has recorded local activity since", () => {
    const resumed = lease({ lastLocalActivityAt: NOW - 1_000, idleSince: NOW - 1_000 })
    expect(isRepeatUnload(NOW - 30_000, readable(resumed), NOW)).toBe(false)
  })

  test("is not a repeat when nothing has been unloaded yet", () => {
    expect(isRepeatUnload(null, readable(lease()), NOW)).toBe(false)
  })

  test("a repeat is not asserted from an unreadable lease set", () => {
    expect(isRepeatUnload(NOW - 30_000, UNREADABLE, NOW)).toBe(false)
  })
})
