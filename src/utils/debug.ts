const STORAGE_KEY = 'bbrf_debug'

const enabled =
  typeof localStorage !== 'undefined' &&
  localStorage.getItem(STORAGE_KEY) === '1'

const prefix = (ns: string) => `[bbrf:${ns}]`

type LogFn = (...args: unknown[]) => void

const noop: LogFn = () => {}

const makeLogger = (ns: string) => {
  const p = prefix(ns)
  const debug: LogFn = enabled
    ? (...args) => console.log(p, ...args)
    : noop
  const info: LogFn = enabled
    ? (...args) => console.info(p, ...args)
    : noop
  const warn: LogFn = (...args) => console.warn(p, ...args)
  const error: LogFn = (...args) => console.error(p, ...args)
  const group = enabled
    ? (label: string, ...args: unknown[]) => console.groupCollapsed(p, label, ...args)
    : (_label: string, ..._args: unknown[]) => {}
  const groupEnd = enabled
    ? () => console.groupEnd()
    : () => {}
  return { debug, info, warn, error, group, groupEnd }
}

export const createLogger = (namespace: string): ReturnType<typeof makeLogger> => makeLogger(namespace)

export const enableDebug = (): void => {
  localStorage.setItem(STORAGE_KEY, '1')
  console.log(prefix('debug'), 'Debug logging enabled. Reload to take effect.')
}

export const disableDebug = (): void => {
  localStorage.removeItem(STORAGE_KEY)
  console.log(prefix('debug'), 'Debug logging disabled. Reload to take effect.')
}

export const isDebugEnabled = (): boolean => enabled
