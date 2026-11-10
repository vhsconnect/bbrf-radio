import { type Plugin, defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'

const API_ROUTES = [
  'favorites',
  'fader',
  'radio-server',
  'bytag',
  'bycountrycode',
  'byname',
  'bytrack',
  'tracks',
  'nowplaying',
  'clicked',
  'write',
] as const

// production builds stay on esbuild and load the bundled ./index.js; in dev, Vite serves the entry as a module instead
const devEntry = (entry: string): Plugin => ({
  name: 'bbrf-dev-entry',
  apply: 'serve',
  transformIndexHtml: html =>
    html.replace(
      '<script src="./index.js"></script>',
      `<script type="module" src="/${entry}"></script>`
    ),
})

export default defineConfig(({ mode }) => {
  // static mode mirrors build:static, the GitHub Pages client that talks to radio-browser directly
  const isStatic = mode === 'static'
  const entry = isStatic ? 'src/Comps/App.Client.tsx' : 'src/Comps/App.tsx'
  const apiTarget = `http://localhost:${loadEnv(mode, '.', '').PORT ?? 4882}`

  return {
    plugins: [react(), devEntry(entry)],
    optimizeDeps: { entries: [entry] },
    server: {
      port: 4884,
      proxy: isStatic
        ? undefined
        : { [`^/(${API_ROUTES.join('|')})(/|\\?|$)`]: apiTarget },
      watch: {
        ignored: [
          '**/server/**',
          '**/server-next/**',
          '**/pages/**',
          '**/result/**',
          '**/.direnv/**',
        ],
      },
    },
  }
})
