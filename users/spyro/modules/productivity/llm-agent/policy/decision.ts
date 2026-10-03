/**
 * The unload-decision seam.
 *
 * One pure question: is it safe to unload the resident model right now? It is a
 * function of leases, in-flight entries, the current time and the thresholds,
 * and of nothing else — no GPU, no backend, no filesystem, no running opencode.
 *
 * That constraint is what makes the policy testable at all, and it is why
 * session activity enters here as lease *output* rather than as decision
 * *input*: opencode filters `event` delivery by working directory, so no
 * instance can observe another's sessions. Coordination happens through
 * published state, and this function only reads published state.
 *
 * The default is refusal. Every branch that cannot prove the resident model is
 * idle returns `unload: false`, because the backend's explicit unload endpoint
 * does not consult its in-flight tracking — it terminates a server mid-request
 * and the client sees a truncated stream. Unavailability must never read as
 * permission.
 */

/**
 * One opencode instance's published statement about itself.
 *
 * Liveness (`alive`) is resolved by the reader, not computed here: deciding
 * whether a process still exists needs the filesystem, and this module must not
 * have one. A lease from a killed instance, or one written before the current
 * boot, arrives already marked `alive: false` and is ignored.
 */
type Lease = {
  /** Separates two plugin instances inside one process. */
  instanceId: string
  pid: number
  alive: boolean
  /** When this instance published its first lease, epoch ms. */
  startedAt: number
  /** Newest local-model activity, epoch ms. `null` = this instance has never run a local model. */
  lastLocalActivityAt: number | null
  /** When a session was last reported busy. `null` while nothing is busy. */
  busySince: number | null
  /** When every session was last reported idle. `null` while anything is busy, or before any status is seen. */
  idleSince: number | null
}

/** A request the backend says is running right now. */
type InflightEntry = {
  id: string
  /** `null` when the backend did not name one. */
  model: string | null
}

/** The lease set as read, including the failure to read it. */
type LeaseSet = { readable: true; leases: Lease[] } | { readable: false; error: string }

type Policy = {
  /** ms without local activity before a lease stops holding the resident model. */
  idleThresholdMs: number
  /**
   * ms an idle observation must have stood still before it may authorise an
   * unload.
   *
   * At the start of a turn a session still reads idle while its opening request
   * is already in flight: `busy` is published *after* dispatch. Without this
   * delay a session that was long idle would be believed the instant it is
   * asked to do more work.
   */
  settleMs: number
}

type Reason =
  | "all-leases-idle"
  | "lease-active"
  | "lease-busy"
  | "lease-settling"
  | "lease-unobserved"
  | "inflight-present"
  | "lease-set-unreadable"
  | "no-live-lease"

type Decision = { unload: boolean; reason: Reason }

const refuse = (reason: Reason): Decision => ({ unload: false, reason })

/**
 * Decide whether the resident model may be unloaded.
 *
 * `now` is passed in rather than read from the clock so that time is an input
 * like any other and the thresholds can be tested without waiting for them.
 */
function shouldUnload(
  leaseSet: LeaseSet,
  inflight: readonly InflightEntry[],
  now: number,
  policy: Policy,
): Decision {
  if (!leaseSet.readable) return refuse("lease-set-unreadable")

  const live = leaseSet.leases.filter((l) => l.alive)
  // A readable set containing nothing alive means our own lease is not in it,
  // which means the publishing side is broken. That is not evidence that
  // nobody is using the model.
  if (live.length === 0) return refuse("no-live-lease")

  // Lease state is checked before the in-flight set: a busy session is the more
  // specific and more actionable explanation, and reporting it avoids sending
  // the reader to the backend for something opencode already knows.
  if (live.some((l) => l.busySince !== null)) return refuse("lease-busy")

  if (inflight.length > 0) return refuse("inflight-present")

  // An instance that has never reported a session is unobserved, and an
  // unobserved instance is not trusted for `settleMs` after it starts: a
  // plugin that has just loaded sits in exactly this state, and believing it
  // would unload the model out from under the turn that is about to start.
  //
  // The guard is deliberately time-bounded. An instance that has been up for
  // longer than the settle delay and has seen no session is simply an open
  // editor; if this stayed a permanent veto, one idle instance would pin the
  // resident model for as long as it stayed open, which is the failure mode
  // this whole policy exists to remove.
  if (live.some((l) => l.idleSince === null && now - l.startedAt < policy.settleMs)) {
    return refuse("lease-unobserved")
  }

  if (live.some((l) => l.idleSince !== null && now - l.idleSince < policy.settleMs)) {
    return refuse("lease-settling")
  }

  if (
    live.some(
      (l) => l.lastLocalActivityAt !== null && now - l.lastLocalActivityAt < policy.idleThresholdMs,
    )
  ) {
    return refuse("lease-active")
  }

  return { unload: true, reason: "all-leases-idle" }
}

/**
 * True when unloading again would repeat a decision already made, rather than
 * follow new information.
 *
 * A turn that fails or is cancelled can report idle more than once, and the
 * policy runs on a timer, so the same idle epoch is otherwise re-decided every
 * tick. One epoch yields one unload attempt.
 */
function isRepeatUnload(lastUnloadAt: number | null, leaseSet: LeaseSet): boolean {
  if (lastUnloadAt === null) return false
  if (!leaseSet.readable) return false
  const live = leaseSet.leases.filter((l) => l.alive)
  return !live.some((l) => l.lastLocalActivityAt !== null && l.lastLocalActivityAt > lastUnloadAt)
}

// The deployed plugin is this file spliced into policy/plugin.ts. Only the seam
// needs a name out here; the rest stays module-local so the concatenation does
// not export two versions of everything.
export { isRepeatUnload, shouldUnload }
export type { Decision, InflightEntry, Lease, LeaseSet, Policy, Reason }
