import { defineConfig } from "vite"
import react from "@vitejs/plugin-react"

// The UI is served by the llm-agent bun server from its root, so the base is
// "/". The build outputs to dist/, which the server serves for every non-API
// path (and which `bun build --compile` embeds into the binary).
export default defineConfig({
  plugins: [react()],
  base: "/",
  server: {
    // In dev, proxy the API to a running llm-agent server.
    proxy: {
      "/api": "http://127.0.0.1:8090",
    },
  },
  build: {
    outDir: "dist",
    emptyOutDir: true,
  },
})
