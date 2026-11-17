import type { ModelEntry, ModelOptions, SpecProfile } from "./api"

// Allowed values, mirroring the core validator's lists.
const CACHE_TYPES = ["f32", "f16", "bf16", "q8_0", "q4_0", "q4_1", "iq4_nl", "q5_0", "q5_1"]
const SPEC_TYPES = [
  "none",
  "draft-simple",
  "draft-eagle3",
  "draft-mtp",
  "draft-dflash",
  "draft-dspark",
  "ngram-simple",
  "ngram-map-k",
  "ngram-map-k4v",
  "ngram-mod",
  "ngram-cache",
]

interface Props {
  key: string
  entry: ModelEntry
  /** The core validator's messages for this model, keyed by field. */
  errors: Record<string, string[]>
  onChange: (key: string, entry: ModelEntry) => void
  onRename: (oldKey: string, newKey: string) => void
}

function num(v: number | undefined | null): string {
  return v === undefined || v === null ? "" : String(v)
}

function parseNum(s: string): number | undefined {
  if (s.trim() === "") return undefined
  const n = Number(s)
  return Number.isFinite(n) ? n : undefined
}

/** The core validator's message(s) for one field, shown inline under it. */
function FieldError({ msgs }: { msgs?: string[] }) {
  if (!msgs || msgs.length === 0) return null
  return <div className="field-error">{msgs.join("\n")}</div>
}

/** A KV-cache-type dropdown (shared by the cache and draft-cache fields). */
function CacheSelect({
  label,
  value,
  onChange,
}: {
  label: string
  value: string | undefined
  onChange: (v: string | undefined) => void
}) {
  return (
    <label className="field">
      <span className="lbl">{label}</span>
      <select value={value ?? ""} onChange={(e) => onChange(e.target.value || undefined)}>
        <option value="">(none)</option>
        {CACHE_TYPES.map((c) => (
          <option key={c} value={c}>{c}</option>
        ))}
      </select>
    </label>
  )
}

export function ModelForm({ key, entry, errors, onChange, onRename }: Props) {
  const opts: ModelOptions = entry.options ?? {}
  const spec: SpecProfile = opts.specProfile ?? {}

  const set = (patch: Partial<ModelEntry>) => onChange(key, { ...entry, ...patch })
  const setOpt = (patch: Partial<ModelOptions>) => onChange(key, { ...entry, options: { ...opts, ...patch } })
  const setSpec = (patch: Partial<SpecProfile>) =>
    onChange(key, { ...entry, options: { ...opts, specProfile: { ...spec, ...patch } } })

  const extraArgsText = (opts.extraArgs ?? []).join("\n")

  return (
    <div className="panel">
      <h2>Model: <span className="mono">{key}</span></h2>
      <FieldError msgs={errors.general} />
      <div className="grid-2">
        <div>
          <label className="field">
            <span className="lbl">Key (rename)</span>
            <input
              className="mono"
              defaultValue={key}
              key={key}
              onBlur={(e) => {
                const nk = e.target.value.trim()
                if (nk && nk !== key) onRename(key, nk)
              }}
            />
          </label>
          <label className="field">
            <span className="lbl">displayName</span>
            <input value={entry.displayName} onChange={(e) => set({ displayName: e.target.value })} />
            <FieldError msgs={errors.displayName} />
          </label>
          <label className="field">
            <span className="lbl">hfRef (owner/repo:quant)</span>
            <input className="mono" value={entry.hfRef} onChange={(e) => set({ hfRef: e.target.value })} />
            <FieldError msgs={errors.hfRef} />
          </label>
          <label className="field">
            <span className="lbl">_comment</span>
            <input value={entry._comment ?? ""} onChange={(e) => set({ _comment: e.target.value || undefined })} />
            <FieldError msgs={errors._comment} />
          </label>
          <label className="field">
            <span className="lbl">ctxSize (int)</span>
            <input className="mono" value={num(opts.ctxSize)} onChange={(e) => setOpt({ ctxSize: parseNum(e.target.value) })} />
            <FieldError msgs={errors.ctxSize} />
          </label>
          <label className="field">
            <span className="lbl">outputLimit (int)</span>
            <input className="mono" value={num(opts.outputLimit)} onChange={(e) => setOpt({ outputLimit: parseNum(e.target.value) })} />
            <FieldError msgs={errors.outputLimit} />
          </label>
          <label className="field">
            <span className="lbl">gpuLayers (int, -1 = all)</span>
            <input className="mono" value={num(opts.gpuLayers)} onChange={(e) => setOpt({ gpuLayers: parseNum(e.target.value) })} />
            <FieldError msgs={errors.gpuLayers} />
          </label>
          <CacheSelect label="cacheType (shorthand)" value={opts.cacheType} onChange={(v) => setOpt({ cacheType: v })} />
          <FieldError msgs={errors.cacheType} />
          <CacheSelect label="cacheTypeK" value={opts.cacheTypeK} onChange={(v) => setOpt({ cacheTypeK: v })} />
          <FieldError msgs={errors.cacheTypeK} />
          <CacheSelect label="cacheTypeV" value={opts.cacheTypeV} onChange={(v) => setOpt({ cacheTypeV: v })} />
          <FieldError msgs={errors.cacheTypeV} />
          <label className="field">
            <span className="lbl">reasoningBudget (int, -1 = unrestricted, blank = null)</span>
            <input
              className="mono"
              value={opts.reasoningBudget === undefined ? "" : String(opts.reasoningBudget)}
              onChange={(e) => {
                const s = e.target.value
                setOpt({ reasoningBudget: s.trim() === "" ? null : parseNum(s) ?? null })
              }}
            />
            <FieldError msgs={errors.reasoningBudget} />
          </label>
          <label className="field">
            <span className="lbl">ttl (int, 0 = never evict)</span>
            <input className="mono" value={num(opts.ttl)} onChange={(e) => setOpt({ ttl: parseNum(e.target.value) })} />
            <FieldError msgs={errors.ttl} />
          </label>
          <label className="field">
            <span className="lbl">temperature (≥ 0)</span>
            <input className="mono" value={num(opts.temperature)} onChange={(e) => setOpt({ temperature: parseNum(e.target.value) })} />
            <FieldError msgs={errors.temperature} />
          </label>
          <label className="field">
            <span className="lbl">topP (0–1)</span>
            <input className="mono" value={num(opts.topP)} onChange={(e) => setOpt({ topP: parseNum(e.target.value) })} />
            <FieldError msgs={errors.topP} />
          </label>
          <label className="field">
            <span className="lbl">topK (int ≥ 0)</span>
            <input className="mono" value={num(opts.topK)} onChange={(e) => setOpt({ topK: parseNum(e.target.value) })} />
            <FieldError msgs={errors.topK} />
          </label>
          <label className="field">
            <span className="lbl">minP (0–1)</span>
            <input className="mono" value={num(opts.minP)} onChange={(e) => setOpt({ minP: parseNum(e.target.value) })} />
            <FieldError msgs={errors.minP} />
          </label>
          <label className="field">
            <span className="lbl">templateOverride</span>
            <input className="mono" value={opts.templateOverride ?? ""} onChange={(e) => setOpt({ templateOverride: e.target.value || undefined })} />
            <FieldError msgs={errors.templateOverride} />
          </label>
          <label className="field">
            <span className="lbl">extraArgs (one per line)</span>
            <textarea
              className="mono"
              rows={4}
              value={extraArgsText}
              onChange={(e) => setOpt({ extraArgs: e.target.value.split("\n").map((s) => s.trim()).filter(Boolean) })}
            />
            <FieldError msgs={errors.extraArgs} />
          </label>
        </div>
        <div>
          <h2 style={{ marginTop: 0 }}>specProfile</h2>
          <FieldError msgs={errors["specProfile"]} />
          <label className="field" style={{ display: "flex", gap: 8, alignItems: "center" }}>
            <input
              type="checkbox"
              style={{ width: "auto" }}
              checked={spec.enabled === true}
              onChange={(e) => setSpec({ enabled: e.target.checked })}
            />
            <span className="lbl" style={{ margin: 0 }}>enabled</span>
          </label>
          <FieldError msgs={errors["specProfile.enabled"]} />
          <label className="field">
            <span className="lbl">specType</span>
            <select value={spec.specType ?? ""} onChange={(e) => setSpec({ specType: e.target.value || undefined })}>
              <option value="">(none)</option>
              {SPEC_TYPES.map((c) => (
                <option key={c} value={c}>{c}</option>
              ))}
            </select>
            <FieldError msgs={errors["specProfile.specType"]} />
          </label>
          <label className="field">
            <span className="lbl">draftModel</span>
            <input className="mono" value={spec.draftModel ?? ""} onChange={(e) => setSpec({ draftModel: e.target.value || undefined })} />
            <FieldError msgs={errors["specProfile.draftModel"]} />
          </label>
          <label className="field">
            <span className="lbl">draftTokensMax (int)</span>
            <input className="mono" value={num(spec.draftTokensMax)} onChange={(e) => setSpec({ draftTokensMax: parseNum(e.target.value) })} />
            <FieldError msgs={errors["specProfile.draftTokensMax"]} />
          </label>
          <label className="field">
            <span className="lbl">draftPMin (0–1)</span>
            <input className="mono" value={num(spec.draftPMin)} onChange={(e) => setSpec({ draftPMin: parseNum(e.target.value) })} />
            <FieldError msgs={errors["specProfile.draftPMin"]} />
          </label>
          <label className="field">
            <span className="lbl">draftPSplit (0–1)</span>
            <input className="mono" value={num(spec.draftPSplit)} onChange={(e) => setSpec({ draftPSplit: parseNum(e.target.value) })} />
            <FieldError msgs={errors["specProfile.draftPSplit"]} />
          </label>
          <label className="field">
            <span className="lbl">draftGpuLayers (int ≥ -1, or auto/all)</span>
            <input
              className="mono"
              value={spec.draftGpuLayers === undefined ? "" : String(spec.draftGpuLayers)}
              onChange={(e) => {
                const s = e.target.value.trim()
                if (s === "auto" || s === "all") setSpec({ draftGpuLayers: s })
                else setSpec({ draftGpuLayers: parseNum(s) })
              }}
            />
            <FieldError msgs={errors["specProfile.draftGpuLayers"]} />
          </label>
          <CacheSelect label="draftCacheTypeK" value={spec.draftCacheTypeK} onChange={(v) => setSpec({ draftCacheTypeK: v })} />
          <FieldError msgs={errors["specProfile.draftCacheTypeK"]} />
          <CacheSelect label="draftCacheTypeV" value={spec.draftCacheTypeV} onChange={(v) => setSpec({ draftCacheTypeV: v })} />
          <FieldError msgs={errors["specProfile.draftCacheTypeV"]} />
        </div>
      </div>
    </div>
  )
}
