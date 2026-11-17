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
    toContain(expected: unknown): void
    toMatchSnapshot(): void
    not: {
      toEqual(expected: unknown): void
      toBe(expected: unknown): void
      toContain(expected: unknown): void
      toMatchSnapshot(): void
    }
  }
}

declare module "node:fs" {
  export function readFileSync(path: string | URL, encoding: "utf8"): string
}

// The `ESNext` lib (no DOM) omits the `URL` global and `import.meta.url`; the
// tests use both to locate the fixture relative to the test file.
declare class URL {
  constructor(input: string, base?: string)
}

interface ImportMeta {
  url: string
}
