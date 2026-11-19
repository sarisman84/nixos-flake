/**
 * The slice of the host runtime this app core and its tests use, declared
 * locally.
 *
 * The flake has no network at evaluation time and `bun-types` is not in the
 * store, so rather than take a type dependency on the published bun types, this
 * declares the handful of shapes the core and its tests touch (the same approach
 * as `policy/ambient.d.ts`).
 */

declare module "bun:test" {
  export function describe(name: string, body: () => void): void
  export function test(name: string, body: () => void | Promise<void>): void
  export function expect(actual: unknown): {
    toEqual(expected: unknown): void
    toBe(expected: unknown): void
    toBeNull(): void
    toBeDefined(): void
    toBeGreaterThan(expected: number): void
    toHaveLength(expected: number): void
    toContain(expected: unknown): void
    toMatchSnapshot(): void
    not: {
      toEqual(expected: unknown): void
      toBe(expected: unknown): void
      toBeNull(): void
      toBeDefined(): void
      toBeGreaterThan(expected: number): void
      toHaveLength(expected: number): void
      toContain(expected: unknown): void
      toMatchSnapshot(): void
    }
  }
}

declare module "node:fs" {
  export interface WriteOptions {
    mode?: number
  }
  export interface Stats {
    mode: number
    isFile(): boolean
    isSymbolicLink(): boolean
    isDirectory(): boolean
  }
  export function readFileSync(path: string | URL, encoding: "utf8"): string
  export function writeFileSync(path: string | URL, data: string, options?: WriteOptions): void
  export function renameSync(oldPath: string | URL, newPath: string | URL): void
  export function mkdirSync(path: string | URL, options?: { recursive?: boolean; mode?: number }): void
  export function readdirSync(path: string | URL): string[]
  export function lstatSync(path: string | URL): Stats
  export function statSync(path: string | URL): Stats
  export function unlinkSync(path: string | URL): void
  export function existsSync(path: string | URL): boolean
  export function mkdtempSync(prefix: string): string
  export function rmSync(path: string | URL, options?: { recursive?: boolean; force?: boolean }): void
  export function symlinkSync(target: string, path: string): void
}

declare module "node:path" {
  export function join(...segments: string[]): string
  export function dirname(p: string): string
  export function normalize(p: string): string
  export function resolve(...segments: string[]): string
}

declare module "node:child_process" {
  export function spawnSync(
    command: string,
    args: string[],
    options?: { input?: string },
  ): { status: number | null; stdout: Uint8Array; stderr: Uint8Array }
}

// The `ESNext` lib (no DOM) omits `process`; the server and its tests use the
// environment, the pid, and `process.kill` (signal 0) for the liveness probe.
declare const process: {
  env: { [key: string]: string | undefined }
  pid: number
  argv: string[]
  kill(pid: number, signal?: number | string): boolean
  exit(code?: number): never
}

declare const console: {
  log(...args: unknown[]): void
  error(...args: unknown[]): void
  warn(...args: unknown[]): void
}

// The `ESNext` lib (no DOM) omits the `URL` global and `import.meta.url`; the
// tests use both to locate the fixture relative to the test file, and the
// server uses `URL` to parse request URLs.
declare class URL {
  constructor(input: string, base?: string)
  href: string
  protocol: string
  host: string
  hostname: string
  port: string
  pathname: string
  search: string
  hash: string
}

interface ImportMeta {
  url: string
  /** bun: the directory of the current module. */
  dir: string
  /** bun: true when this module is the program entry point. */
  main: boolean
}

// The `ESNext` lib (no DOM) omits `fetch`; the status reader and its tests use
// it to poll the llama-swap backend. Declared minimally, injected so tests can
// substitute a fake.
declare class Response {
  constructor(body?: string, init?: { status?: number; headers?: Record<string, string> })
  ok: boolean
  status: number
  headers: { get(name: string): string | null }
  json(): Promise<unknown>
  text(): Promise<string>
}
interface RequestInit {
  method?: string
  headers?: Record<string, string>
  body?: string
}
declare function fetch(input: string, init?: RequestInit): Promise<Response>

// The bun runtime's server API, declared minimally. The `serve` call returns a
// server that can be stopped; the test starts one on an ephemeral port and
// drives it with real HTTP requests.
interface BunServer {
  port: number
  stop(): void
}
interface Bun {
  serve(options: {
    port: number
    hostname?: string
    fetch(req: Request): Response | Promise<Response>
  }): BunServer
}
declare const Bun: Bun
interface Request {
  method: string
  url: string
  json(): Promise<unknown>
  text(): Promise<string>
}
