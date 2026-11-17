import type { ModelEntry } from "./api"

interface Props {
  models: Record<string, ModelEntry>
  selected: string | null
  isDefault: (key: string) => boolean
  onSelect: (key: string) => void
  onAdd: () => void
  onRemove: (key: string) => void
}

export function ModelTable({ models, selected, isDefault, onSelect, onAdd, onRemove }: Props) {
  const keys = Object.keys(models).sort()
  return (
    <div className="panel">
      <div className="row spread">
        <h2>Local models</h2>
        <button onClick={onAdd}>+ Add model</button>
      </div>
      <table>
        <thead>
          <tr>
            <th>Key</th>
            <th>Display name</th>
            <th>hfRef</th>
            <th>ctx</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          {keys.map((key) => {
            const m = models[key]
            return (
              <tr
                key={key}
                className={selected === key ? "selected" : ""}
                onClick={() => onSelect(key)}
                style={{ cursor: "pointer" }}
              >
                <td className="mono">
                  {key}
                  {isDefault(key) ? <span className="muted"> · default</span> : null}
                </td>
                <td>{m.displayName}</td>
                <td className="mono">{m.hfRef}</td>
                <td className="mono">{m.options?.ctxSize ?? "—"}</td>
                <td onClick={(e) => e.stopPropagation()}>
                  <button className="danger" onClick={() => onRemove(key)}>
                    remove
                  </button>
                </td>
              </tr>
            )
          })}
          {keys.length === 0 ? (
            <tr>
              <td colSpan={5} className="muted">
                no local models
              </td>
            </tr>
          ) : null}
        </tbody>
      </table>
    </div>
  )
}
