/**
 * The slice of the *runtime* this policy uses, declared locally.
 *
 * The flake has no network at evaluation time and the published opencode types
 * are not in the store, so this module cannot take a type dependency on them.
 * Rather than import types it cannot resolve, it declares the handful of
 * node/bun/process shapes it touches.
 *
 * The opencode *host API* shapes (the v2 plugin context, the event envelope,
 * the `context` hook) are inlined in `plugin.ts` next to the code that reads
 * them, with the host facts documented there. Keeping them local to the reader
 * means a host change shows up at the exact line that breaks, not in a shared
 * declaration that drifts.
 *
 * If a future opencode or bun moves one of these runtime shapes, `nix flake
 * check` will still pass — this file is the reason to re-probe rather than
 * trust the build.
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
  export function writeFileSync(path: string, data: string, options?: { mode?: number; flag?: string }): void
  export function renameSync(from: string, to: string): void
  export function rmSync(path: string, options: { force?: boolean; recursive?: boolean }): void
}

declare module "node:os" {
  export function homedir(): string
  export function tmpdir(): string
}

declare module "node:path" {
  export function join(...parts: string[]): string
}


declare const process: {
  pid: number
  env: Record<string, string | undefined>
  kill(pid: number, signal: number): void
}

declare function setInterval(handler: () => void, ms: number): { unref(): void }
declare function clearInterval(handle: { unref(): void }): void
declare function setTimeout(handler: () => void, ms?: number): number
declare function clearTimeout(handle: number): void
declare function fetch(
  url: string,
  init?: { method?: string; signal?: AbortSignal },
): Promise<{ ok: boolean; status: number }>

declare class AbortController {
  readonly signal: AbortSignal
  abort(): void
}
declare interface AbortSignal {
  readonly aborted: boolean
}

declare const console: { log(...args: unknown[]): void }
