/**
 * Atomic file writes.
 *
 * The unload-policy plugin already writes its leases and heartbeat through a
 * temp file + rename so a reader never observes a half-written file. The app
 * does the same for the registry and the generated configs, and goes one step
 * further for the opencode/llama-swap files: it replaces the Nix-store symlink
 * the flake leaves behind with a regular file it owns, because opencode's
 * config watcher watches the *directory* — a write through a symlink to a
 * target outside that directory is invisible to it (settled by #91).
 */
import {
  lstatSync,
  mkdirSync,
  renameSync,
  unlinkSync,
  writeFileSync,
} from "node:fs"
import { dirname } from "node:path"

/**
 * Write `content` to `path` atomically: write a sibling temp file, then rename
 * it over `path`. A reader never observes a partial file. `mode` is the file
 * mode (0o600 for the registry and the generated configs). Missing parent
 * directories are created.
 */
export function writeAtomic(path: string, content: string, mode = 0o600): void {
  mkdirSync(dirname(path), { recursive: true })
  const tmp = `${path}.tmp`
  try {
    writeFileSync(tmp, content, { mode })
    renameSync(tmp, path)
  } catch (error) {
    // Do not leave a stale temp file behind if the write or rename failed.
    try {
      unlinkSync(tmp)
    } catch {
      // The temp file was never created (or already renamed); nothing to clean.
    }
    throw error
  }
}

/**
 * Write `content` to `path` as a REGULAR file the app owns. If `path` is a
 * symlink (the Nix-store symlink the flake leaves behind), remove the link
 * first so the write lands as a real file in the watched directory. Writing
 * through the symlink would update the store target and be invisible to
 * opencode's directory watcher, leaving the model list stale.
 */
export function writeOwnedFile(path: string, content: string, mode = 0o600): void {
  try {
    if (lstatSync(path).isSymbolicLink()) unlinkSync(path)
  } catch {
    // `path` does not exist yet — nothing to remove.
  }
  writeAtomic(path, content, mode)
}
