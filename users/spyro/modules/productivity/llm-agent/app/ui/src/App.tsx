import { useCallback, useEffect, useRef, useState } from "react"
import { api, fieldErrorsFor, type Artifacts, type RegistryData, type StatusResponse } from "./api"
import { StatusStrip } from "./StatusStrip"
import { ModelTable } from "./ModelTable"
import { ModelForm } from "./ModelForm"
import { CloudList, DefaultPolicyEditors } from "./CloudList"
import { OpencodeEditor } from "./OpencodeEditor"
import { ApplyPanel, type ApplyResult } from "./ApplyPanel"

const STATUS_INTERVAL_MS = 3000

export default function App() {
  const [registry, setRegistry] = useState<RegistryData | null>(null)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [status, setStatus] = useState<StatusResponse | null>(null)
  const [selected, setSelected] = useState<string | null>(null)
  const [errors, setErrors] = useState<string[]>([])
  const [preview, setPreview] = useState<Artifacts | null>(null)
  const [applyResult, setApplyResult] = useState<ApplyResult | null>(null)
  const [busy, setBusy] = useState(false)
  const [jsonc, setJsonc] = useState<string | null>(null)
  const [opencodeJson, setOpencodeJson] = useState<string | null>(null)
  const loaded = useRef(false)
  // Monotonic guard so a slow validate response can't clobber a newer one.
  const validateSeq = useRef(0)

  // Load the registry + opencode.jsonc + the generated opencode.json once.
  useEffect(() => {
    if (loaded.current) return
    loaded.current = true
    Promise.all([api.getRegistry(), api.getJsonc(), api.getOpencodeJson()])
      .then(([reg, jc, oj]) => {
        if (reg.registry) {
          setRegistry(reg.registry)
          setSelected(Object.keys(reg.registry.local).sort()[0] ?? null)
        } else {
          setLoadError(reg.errors.join("\n") || "no registry")
        }
        setJsonc(jc.content)
        setOpencodeJson(oj.content)
      })
      .catch((e) => setLoadError(String(e)))
  }, [])

  // Poll the status strip.
  useEffect(() => {
    let stop = false
    const tick = () => {
      api.status().then((s) => { if (!stop) setStatus(s) }).catch(() => {})
    }
    tick()
    const id = setInterval(tick, STATUS_INTERVAL_MS)
    return () => {
      stop = true
      clearInterval(id)
    }
  }, [])

  const patch = useCallback((p: Partial<RegistryData>) => {
    setRegistry((r) => (r ? { ...r, ...p } : r))
    setApplyResult(null)
  }, [])

  const setModel = useCallback((key: string, entry: RegistryData["local"][string]) => {
    setRegistry((r) => (r ? { ...r, local: { ...r.local, [key]: entry } } : r))
    setApplyResult(null)
  }, [])

  const renameModel = useCallback((oldKey: string, newKey: string) => {
    setRegistry((r) => {
      if (!r || r.local[oldKey] === undefined) return r
      const local = { ...r.local }
      local[newKey] = local[oldKey]
      delete local[oldKey]
      const def = r.default.name === oldKey ? { ...r.default, name: newKey } : r.default
      return { ...r, local, default: def }
    })
    setSelected(newKey)
    setApplyResult(null)
  }, [])

  const addModel = useCallback(() => {
    setRegistry((r) => {
      if (!r) return r
      let i = 1
      let key = `model-${i}`
      while (r.local[key] !== undefined) {
        i++
        key = `model-${i}`
      }
      setSelected(key)
      return { ...r, local: { ...r.local, [key]: { displayName: key, hfRef: "owner/repo:quant" } } }
    })
  }, [])

  const removeModel = useCallback((key: string) => {
    setRegistry((r) => {
      if (!r) return r
      const local = { ...r.local }
      delete local[key]
      return { ...r, local }
    })
    setSelected((s) => (s === key ? null : s))
  }, [])

  const runValidate = useCallback(async (reg: RegistryData) => {
    const id = ++validateSeq.current
    setBusy(true)
    try {
      const res = await api.validate(reg)
      if (validateSeq.current === id) {
        setErrors(res.errors)
        setApplyResult(null)
      }
    } catch (e) {
      if (validateSeq.current === id) setErrors([String(e)])
    } finally {
      if (validateSeq.current === id) setBusy(false)
    }
  }, [])

  // Auto-validate (debounced) as the user edits, so the core validator's
  // messages show inline without a manual step. The manual Validate button
  // forces an immediate run of the same path.
  useEffect(() => {
    if (!registry) return
    const t = setTimeout(() => {
      void runValidate(registry)
    }, 400)
    return () => clearTimeout(t)
  }, [registry, runValidate])

  const doValidate = useCallback(() => {
    if (registry) void runValidate(registry)
  }, [registry, runValidate])

  const doPreview = useCallback(async () => {
    if (!registry) return
    setBusy(true)
    try {
      const res = await api.preview(registry)
      if (res.ok && res.artifacts) {
        setPreview(res.artifacts)
        setErrors([])
      } else {
        setErrors(res.errors ?? ["preview failed"])
        setPreview(null)
      }
    } catch (e) {
      setErrors([String(e)])
    } finally {
      setBusy(false)
    }
  }, [registry])

  const doApply = useCallback(async () => {
    if (!registry) return
    setBusy(true)
    setApplyResult(null)
    try {
      const res = await api.apply(registry)
      setApplyResult({
        ok: res.ok,
        message: res.message,
        reloaded: res.reloaded,
        errors: res.errors,
        busyLeases: res.busyLeases,
      })
      if (res.ok) {
        setErrors([])
        // The apply rewrote the generated opencode.json; refresh the read-only
        // view so it shows what is now on disk.
        api.getOpencodeJson().then((oj) => setOpencodeJson(oj.content)).catch(() => {})
      }
    } catch (e) {
      setApplyResult({ ok: false, errors: [String(e)] })
    } finally {
      setBusy(false)
    }
  }, [registry])

  const doExport = useCallback(() => {
    window.location.href = api.exportUrl()
  }, [])

  const doImport = useCallback(async (content: string) => {
    setBusy(true)
    try {
      const res = await api.importRegistry(content)
      if (res.ok) {
        const fresh = await api.getRegistry()
        if (fresh.registry) {
          setRegistry(fresh.registry)
          setSelected(Object.keys(fresh.registry.local).sort()[0] ?? null)
        }
        setApplyResult({ ok: true, message: "imported — registry replaced (not applied)" })
        setErrors([])
      } else {
        setApplyResult({ ok: false, errors: res.errors })
      }
    } catch (e) {
      setApplyResult({ ok: false, errors: [String(e)] })
    } finally {
      setBusy(false)
    }
  }, [])

  const doJsoncChange = useCallback((content: string) => {
    setJsonc(content)
    api.putJsonc(content).catch(() => {})
  }, [])

  if (loadError) {
    return (
      <div>
        <h1>llm-agent <span className="sub">registry editor</span></h1>
        <div className="errors">{loadError}</div>
        <div className="muted">
          No <span className="mono">~/.config/llm-agent/registry.json</span> found. Import one, or create it
          from the flake's registry.
        </div>
      </div>
    )
  }

  if (!registry) {
    return (
      <div>
        <h1>llm-agent <span className="sub">registry editor</span></h1>
        <div className="muted">loading…</div>
      </div>
    )
  }

  const selectedEntry = selected ? registry.local[selected] : null
  const fieldErrors = selected ? fieldErrorsFor(errors, selected) : {}

  return (
    <div>
      <h1>
        llm-agent <span className="sub">registry editor · 127.0.0.1:8090</span>
      </h1>
      <StatusStrip status={status} />
      <ModelTable
        models={registry.local}
        selected={selected}
        isDefault={(k) => registry.default.provider === "llama.cpp" && registry.default.name === k}
        onSelect={setSelected}
        onAdd={addModel}
        onRemove={removeModel}
      />
      {selected && selectedEntry ? (
        <ModelForm
          key={selected}
          entry={selectedEntry}
          errors={fieldErrors}
          onChange={setModel}
          onRename={renameModel}
        />
      ) : null}
      <CloudList cloud={registry.cloud} onChange={(cloud) => patch({ cloud })} />
      <DefaultPolicyEditors registry={registry} onChange={patch} />
      <OpencodeEditor
        opencode={registry.opencode}
        jsonc={jsonc}
        opencodeJson={opencodeJson}
        onChange={(opencode) => patch({ opencode })}
        onJsoncChange={doJsoncChange}
      />
      <ApplyPanel
        errors={errors}
        status={status}
        preview={preview}
        applyResult={applyResult}
        busy={busy}
        onValidate={doValidate}
        onPreview={doPreview}
        onApply={doApply}
        onExport={doExport}
        onImport={doImport}
      />
    </div>
  )
}
