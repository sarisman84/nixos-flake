import type { StatusResponse } from "./api"

// A heartbeat older than this is considered stale: the unload-policy plugin
// writes it on activity, so a stale one means the plugin is not running (the
// known opencode 2.2.6 load failure).
const STALE_MS = 120_000

function fmtAge(ms: number | null): string {
  if (ms === null) return "unknown"
  if (ms < 1000) return `${ms}ms`
  const s = Math.floor(ms / 1000)
  if (s < 60) return `${s}s`
  const m = Math.floor(s / 60)
  if (m < 60) return `${m}m ${s % 60}s`
  return `${Math.floor(m / 60)}h ${m % 60}m`
}

export function StatusStrip({ status }: { status: StatusResponse | null }) {
  if (!status) {
    return (
      <div className="panel">
        <h2>Status</h2>
        <div className="muted">loading…</div>
      </div>
    )
  }
  const { backend, heartbeat, leases } = status
  const resident = backend.running[0]
  const hbStale = heartbeat.present && heartbeat.ageMs !== null && heartbeat.ageMs > STALE_MS
  const hbDot = !heartbeat.present ? "down" : hbStale ? "stale" : "ok"

  return (
    <div className="panel">
      <h2>Status</h2>
      <div className="row">
        <div className="kv">
          <span className="k">Backend</span>
          <span>
            <span className={`dot ${backend.up ? "ok" : "down"}`} />
            {backend.up ? "up" : "down"}
            {backend.version ? <span className="muted"> · v{backend.version}</span> : null}
          </span>
        </div>
        <div className="kv">
          <span className="k">Resident model</span>
          <span className="mono">
            {resident ? `${resident.model} (${resident.state})` : <span className="muted">none</span>}
          </span>
        </div>
        <div className="kv">
          <span className="k">Unload heartbeat</span>
          <span>
            <span className={`dot ${hbDot}`} />
            {heartbeat.present ? (
              <>
                {fmtAge(heartbeat.ageMs)} old
                {hbStale ? <span className="muted"> · stale (plugin not running?)</span> : null}
              </>
            ) : (
              <span className="muted">absent</span>
            )}
          </span>
        </div>
        <div className="kv">
          <span className="k">Leases</span>
          <span>
            {leases.busy ? (
              <span style={{ color: "var(--warn)" }}>
                busy: {leases.busyLeases.map((l) => l.instanceId).join(", ")}
              </span>
            ) : leases.readable ? (
              <span className="muted">idle</span>
            ) : (
              <span style={{ color: "var(--err)" }}>unreadable</span>
            )}
          </span>
        </div>
      </div>
    </div>
  )
}
