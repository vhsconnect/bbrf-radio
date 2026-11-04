import * as esbuild from 'esbuild'

const RELOAD_PORT = Number(process.env.RELOAD_PORT ?? 8097)

const ctx = await esbuild.context({
  entryPoints: ['src/Comps/App.tsx'],
  bundle: true,
  loader: { '.mjs': 'js' },
  outfile: 'index.js',
  logLevel: 'info',
  // dev builds only: reload the page whenever esbuild rebuilds
  banner: {
    js: `new EventSource('http://' + location.hostname + ':${RELOAD_PORT}/esbuild').addEventListener('change', () => location.reload());`,
  },
})

await ctx.watch()

// serves only the reload event stream, the app server keeps serving index.js
await ctx.serve({
  port: RELOAD_PORT,
  cors: { origin: ['http://localhost:*', 'http://127.0.0.1:*'] },
})
