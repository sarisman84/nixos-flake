import { useState } from "react"
import type { RegistryData } from "./api"

interface Props {
  opencode: RegistryData["opencode"]
  jsonc: string | null
  /** The generated opencode.json currently on disk (read-only here). */
  opencodeJson: string | null
  onChange: (opencode: RegistryData["opencode"]) => void
  onJsoncChange: (content: string) => void
}

export function OpencodeEditor({ opencode, jsonc, opencodeJson, onChange, onJsoncChange }: Props) {
  const [mcpText, setMcpText] = useState(() => JSON.stringify(opencode.mcp ?? {}, null, 2))
  const [mcpError, setMcpError] = useState<string | null>(null)
  const pluginText = (opencode.plugin ?? []).join("\n")

  const applyMcp = (text: string) => {
    setMcpText(text)
    try {
      const parsed = JSON.parse(text)
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
        setMcpError(null)
        onChange({ ...opencode, mcp: parsed })
      } else {
        setMcpError("mcp must be a JSON object")
      }
    } catch (e) {
      setMcpError(String(e))
    }
  }

  return (
    <div className="panel">
      <h2>opencode extras</h2>
      <label className="field">
        <span className="lbl">MCP servers (JSON object)</span>
        <textarea className="mono" rows={8} value={mcpText} onChange={(e) => applyMcp(e.target.value)} />
        {mcpError ? <div className="errors">{mcpError}</div> : null}
      </label>
      <label className="field">
        <span className="lbl">plugin list (one per line)</span>
        <textarea
          className="mono"
          rows={3}
          value={pluginText}
          onChange={(e) =>
            onChange({ ...opencode, plugin: e.target.value.split("\n").map((s) => s.trim()).filter(Boolean) })
          }
        />
      </label>
      <label className="field">
        <span className="lbl">opencode.json (generated — rewritten on Apply, not edited here)</span>
        <pre className="artifact mono">{opencodeJson ?? "(not written yet — run Apply)"}</pre>
      </label>
      <label className="field">
        <span className="lbl">
          opencode.jsonc (user-owned override — loads last, wins for shared keys)
        </span>
        <textarea
          className="mono"
          rows={5}
          value={jsonc ?? ""}
          placeholder="(no opencode.jsonc)"
          onChange={(e) => onJsoncChange(e.target.value)}
        />
      </label>
    </div>
  )
}
