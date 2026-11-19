import type { RegistryData } from "./api"

interface Props {
  cloud: Record<string, string>
  onChange: (cloud: Record<string, string>) => void
}

export function CloudList({ cloud, onChange }: Props) {
  const keys = Object.keys(cloud).sort()
  const setKey = (oldKey: string, newKey: string) => {
    const next: Record<string, string> = {}
    for (const [k, v] of Object.entries(cloud)) next[k === oldKey ? newKey : k] = v
    onChange(next)
  }
  return (
    <div className="panel">
      <div className="row spread">
        <h2>Cloud models</h2>
        <button
          onClick={() => {
            const next = { ...cloud }
            let i = 1
            while (next[`cloud-${i}`] !== undefined) i++
            next[`cloud-${i}`] = `cloud-${i}`
            onChange(next)
          }}
        >
          + Add
        </button>
      </div>
      <table>
        <thead>
          <tr>
            <th>Key</th>
            <th>Model id</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          {keys.map((k) => (
            <tr key={k}>
              <td>
                <input
                  className="mono"
                  defaultValue={k}
                  key={k}
                  style={{ width: "45%" }}
                  onBlur={(e) => {
                    const nk = e.target.value.trim()
                    if (nk && nk !== k) setKey(k, nk)
                  }}
                />
              </td>
              <td>
                <input
                  className="mono"
                  value={cloud[k]}
                  onChange={(e) => onChange({ ...cloud, [k]: e.target.value })}
                />
              </td>
              <td>
                <button className="danger" onClick={() => {
                  const next = { ...cloud }
                  delete next[k]
                  onChange(next)
                }}>
                  remove
                </button>
              </td>
            </tr>
          ))}
          {keys.length === 0 ? (
            <tr>
              <td colSpan={3} className="muted">no cloud models</td>
            </tr>
          ) : null}
        </tbody>
      </table>
    </div>
  )
}

/** A positive-integer policy threshold input (idle/settle seconds). */
function PolicyNumber({
  label,
  value,
  onValue,
}: {
  label: string
  value: number
  onValue: (n: number) => void
}) {
  return (
    <label className="field">
      <span className="lbl">{label}</span>
      <input
        className="mono"
        value={String(value)}
        onChange={(e) => {
          const n = Number(e.target.value)
          if (Number.isFinite(n)) onValue(n)
        }}
      />
    </label>
  )
}

interface DPProps {
  registry: RegistryData
  onChange: (patch: Partial<RegistryData>) => void
}

export function DefaultPolicyEditors({ registry, onChange }: DPProps) {
  const d = registry.default
  const p = registry.unloadPolicy
  const localKeys = Object.keys(registry.local).sort()
  const cloudKeys = Object.keys(registry.cloud).sort()
  const providerKeys = ["llama.cpp", "opencode"]
  const namesFor = (provider: string) => (provider === "llama.cpp" ? localKeys : provider === "opencode" ? cloudKeys : [])
  return (
    <div className="grid-2">
      <div className="panel">
        <h2>Default model</h2>
        <label className="field">
          <span className="lbl">provider</span>
          <select
            value={d.provider}
            onChange={(e) => onChange({ default: { provider: e.target.value, name: d.name } })}
          >
            {providerKeys.map((p) => (
              <option key={p} value={p}>{p}</option>
            ))}
          </select>
        </label>
        <label className="field">
          <span className="lbl">name</span>
          <select
            value={d.name}
            onChange={(e) => onChange({ default: { provider: d.provider, name: e.target.value } })}
          >
            {namesFor(d.provider).map((n) => (
              <option key={n} value={n}>{n}</option>
            ))}
            {namesFor(d.provider).includes(d.name) === false && d.name ? (
              <option value={d.name}>{d.name} (unregistered)</option>
            ) : null}
          </select>
        </label>
      </div>
      <div className="panel">
        <h2>Unload policy</h2>
        <PolicyNumber
          label="idleThresholdSeconds (int &gt; 0)"
          value={p.idleThresholdSeconds}
          onValue={(n) => onChange({ unloadPolicy: { ...p, idleThresholdSeconds: n } })}
        />
        <PolicyNumber
          label="settleSeconds (int &gt; 0)"
          value={p.settleSeconds}
          onValue={(n) => onChange({ unloadPolicy: { ...p, settleSeconds: n } })}
        />
      </div>
    </div>
  )
}
