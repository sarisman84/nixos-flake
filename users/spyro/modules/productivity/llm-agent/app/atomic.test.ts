import { describe, expect, test } from "bun:test"
import {
  existsSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  statSync,
  symlinkSync,
  writeFileSync,
} from "node:fs"
import { join } from "node:path"
import { writeAtomic, writeOwnedFile } from "./atomic.js"

// A scratch directory per test, removed afterwards.
function scratch(): string {
  return mkdtempSync("/tmp/opencode/atomic-")
}

describe("writeAtomic", () => {
  test("writes the content and sets mode 600", () => {
    const dir = scratch()
    try {
      const p = join(dir, "registry.json")
      writeAtomic(p, '{"a":1}')
      expect(readFileSync(p, "utf8")).toBe('{"a":1}')
      expect(statSync(p).mode & 0o777).toBe(0o600)
    } finally {
      rmSync(dir, { recursive: true, force: true })
    }
  })

  test("creates missing parent directories", () => {
    const dir = scratch()
    try {
      const p = join(dir, "a", "b", "c.json")
      writeAtomic(p, "x")
      expect(readFileSync(p, "utf8")).toBe("x")
    } finally {
      rmSync(dir, { recursive: true, force: true })
    }
  })

  test("leaves no temp file behind on success", () => {
    const dir = scratch()
    try {
      const p = join(dir, "f.json")
      writeAtomic(p, "x")
      expect(existsSync(`${p}.tmp`)).toBe(false)
    } finally {
      rmSync(dir, { recursive: true, force: true })
    }
  })

  test("overwrites an existing regular file", () => {
    const dir = scratch()
    try {
      const p = join(dir, "f.json")
      writeFileSync(p, "old")
      writeAtomic(p, "new")
      expect(readFileSync(p, "utf8")).toBe("new")
    } finally {
      rmSync(dir, { recursive: true, force: true })
    }
  })
})

describe("writeOwnedFile", () => {
  test("replaces a Nix-store symlink with a regular file it owns", () => {
    const dir = scratch()
    try {
      // A target outside the watched directory, like the Nix store.
      mkdirSync(join(dir, "store"), { recursive: true })
      const target = join(dir, "store", "opencode.json")
      writeFileSync(target, "store-content")
      const link = join(dir, "opencode", "opencode.json")
      // create the opencode dir + the symlink
      mkdirSync(join(dir, "opencode"), { recursive: true })
      symlinkSync(target, link)
      expect(lstatSync(link).isSymbolicLink()).toBe(true)

      writeOwnedFile(link, '{"owned":true}')

      // The symlink is gone; a regular file with the new content is in its place.
      expect(lstatSync(link).isSymbolicLink()).toBe(false)
      expect(lstatSync(link).isFile()).toBe(true)
      expect(readFileSync(link, "utf8")).toBe('{"owned":true}')
      expect(statSync(link).mode & 0o777).toBe(0o600)
      // The store target is untouched.
      expect(readFileSync(target, "utf8")).toBe("store-content")
    } finally {
      rmSync(dir, { recursive: true, force: true })
    }
  })

  test("writes a fresh regular file when none exists", () => {
    const dir = scratch()
    try {
      const p = join(dir, "opencode", "opencode.jsonc")
      writeOwnedFile(p, '{"plugins":[]}')
      expect(lstatSync(p).isFile()).toBe(true)
      expect(readFileSync(p, "utf8")).toBe('{"plugins":[]}')
    } finally {
      rmSync(dir, { recursive: true, force: true })
    }
  })
})
