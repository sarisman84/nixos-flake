import { useState } from "react"
import type { Artifacts, StatusResponse } from "./api"

export interface ApplyResult {
  ok: boolean
  message?: string
  reloaded?: boolean
  errors?: string[]
  /** Live busy leases that were interrupted by the reload (named concretely). */
  busyLeases?: string[]
}

interface Props {
  errors: string[]
  status: StatusResponse | null
  preview: Artifacts | null
  applyResult: ApplyResult | null
  busy: boolean
  onValidate: () => void
  onPreview: () => void
  onApply: () => void
  onExport: () => void
  onImport: (content: string) => void
}

export function ApplyPanel({
  errors,
  status,
  preview,
  applyResult,
  busy,
  onValidate,
  onPreview,
  onApply,
  onExport,
  onImport,
}: Props) {
  const [confirming, setConfirming] = useState(false)
  const [importText, setImportText] = useState("")
  const busyLease = status?.leases.busy === true
  const canApply = errors.length === 0 && !busy

  return (
    <div className="panel">
      <h2>Apply</h2>
      <div className="row">
        <button onClick={onValidate} disabled={busy}>Validate</button>
        <button onClick={onPreview} disabled={busy}>Preview artefacts</button>
        <button className="primary" onClick={() => setConfirming(true)} disabled={!canApply}>
          Apply…
        </button>
        <span style={{ flex: 1 }} />
        <button onClick={onExport} disabled={busy}>Export registry</button>
        <label className="field" style={{ margin: 0, display: "flex", gap: 6, alignItems: "center" }}>
          <input
            type="file"
            accept="application/json,.json"
            style={{ width: "auto" }}
            onChange={(e) => {
              const f = e.target.files?.[0]
              if (!f) return
              f.text().then((t) => {
                setImportText(t)
                onImport(t)
              })
            }}
          />
          <span className="muted" style={{ fontSize: 12 }}>import</span>
        </label>
      </div>

      {errors.length > 0 ? (
        <div className="errors">{errors.join("\n")}</div>
      ) : null}

      {busyLease ? (
        <div className="errors" style={{ borderColor: "var(--warn)", background: "rgba(210,153,34,0.1)" }}>
          A live lease is busy right now ({status!.leases.busyLeases.map((l) => l.instanceId).join(", ")}).
          Applying will evict the resident model and interrupt that session.
        </div>
      ) : null}

      {preview ? (
        <div>
          <h2 style={{ marginTop: 12 }}>Preview (generated artefacts)</h2>
          <div className="kv"><span className="k">config.yaml</span></div>
          <pre className="artifact mono">{preview.configYaml}</pre>
          <div className="kv"><span className="k">opencode.json</span></div>
          <pre className="artifact mono">{preview.opencodeJson}</pre>
          <div className="kv"><span className="k">unload-policy.json</span></div>
          <pre className="artifact mono">{preview.unloadPolicyJson}</pre>
        </div>
      ) : null}

      {applyResult ? (
        applyResult.ok ? (
          <div className="notice">
            {applyResult.message}
            {applyResult.reloaded === false
              ? " (warning: the backend reload signal failed — run `systemctl --user kill -s HUP llama-swap` manually)"
              : ""}
            {applyResult.busyLeases && applyResult.busyLeases.length > 0
              ? ` (interrupted busy session(s): ${applyResult.busyLeases.join(", ")})`
              : ""}
          </div>
        ) : (
          <div className="errors">{(applyResult.errors ?? []).join("\n")}</div>
        )
      ) : null}

      {confirming ? (
        <div className="panel" style={{ marginTop: 12, borderColor: "var(--warn)" }}>
          <strong>Apply and reload?</strong>
          <p className="muted" style={{ margin: "8px 0" }}>
            This writes <span className="mono">registry.json</span>, regenerates{" "}
            <span className="mono">config.yaml</span>, <span className="mono">opencode.json</span>,{" "}
            <span className="mono">opencode.jsonc</span> and <span className="mono">unload-policy.json</span>,
            then sends <span className="mono">systemctl --user kill -s HUP llama-swap</span> to reload the
            backend. The reload <em>evicts the resident model</em> (exactly like a restart). Running opencode
            instances pick the new config up within a second.
          </p>
          {busyLease && status ? (
            <p className="muted" style={{ margin: "0 0 8px", color: "var(--warn)" }}>
              A live lease is busy right now ({status.leases.busyLeases.map((l) => l.instanceId).join(", ")}).
              Applying will evict the resident model and <em>interrupt that session</em>.
            </p>
          ) : null}
          <div className="row">
            <button className="primary" onClick={() => { setConfirming(false); onApply() }} disabled={busy}>
              Yes, apply
            </button>
            <button onClick={() => setConfirming(false)} disabled={busy}>Cancel</button>
          </div>
        </div>
      ) : null}

      {importText ? (
        <div className="muted" style={{ fontSize: 12, marginTop: 8 }}>
          import buffer: {importText.length} chars
        </div>
      ) : null}
    </div>
  )
}
