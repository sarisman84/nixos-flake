/**
 * The slice of the host runtime this policy uses, declared locally.
 *
 * The flake has no network at evaluation time and `@opencode-ai/plugin` is not
 * in the store, so this module cannot take a type dependency on the published
 * opencode types. Rather than import types it cannot resolve, it declares the
 * handful of shapes it touches.
 *
 * These declarations were checked against opencode 1.18.31 by running a probe
 * plugin against the real binary, not read off documentation:
 *
 *   - `session.status` carries `{ sessionID, status: { type: "busy" | "idle" | "retry" } }`.
 *   - `chat.params` carries `model.providerID` / `model.id`.
 *   - `chat.message` does *not* carry a model — its `model` is absent, which is
 *     why model selection is read from `chat.params`.
 *   - `client.app.log({ body: { service, level, message, extra } })`.
 *   - The plugin factory is called more than once per process, so it must be
 *     idempotent about side effects.
 *
 * If a future opencode moves one of these, `nix flake check` will still pass —
 * this file is the reason to re-probe rather than trust the build.
 */

declare module "bun:test" {
  export function describe(name: string, body: () => void): void
  export function beforeEach(body: () => void): void
  export function afterEach(body: () => void): void
  export function test(name: string, body: () => void | Promise<void>): void
  export function expect(actual: unknown): {
    toEqual(expected: unknown): void
    toBe(expected: unknown): void
    toBeGreaterThan(expected: number): void
  }
}

declare module "node:fs" {
  export function mkdirSync(path: string, options: { recursive: true; mode?: number }): void
  export function mkdtempSync(prefix: string): string
  export function existsSync(path: string): boolean
  export function readdirSync(path: string): string[]
  export function readFileSync(path: string, encoding: "utf8"): string
  export function writeFileSync(path: string, data: string, options?: { mode?: number }): void
  export function renameSync(from: string, to: string): void
  export function rmSync(path: string, options: { force?: boolean }): void
}

declare module "node:os" {
  export function tmpdir(): string
}

declare module "node:path" {
  export function join(...parts: string[]): string
}

declare module "node:os" {
  export function homedir(): string
}


declare const process: {
  pid: number
  env: Record<string, string | undefined>
  kill(pid: number, signal: number): void
}

declare function setInterval(handler: () => void, ms: number): { unref(): void }
declare function clearInterval(handle: { unref(): void }): void
declare function fetch(
  url: string,
  init?: { method?: string; signal?: AbortSignal },
): Promise<{ ok: boolean; status: number }>

declare const console: { log(...args: unknown[]): void }
