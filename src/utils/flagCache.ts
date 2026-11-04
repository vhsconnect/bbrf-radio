const UPSTREAM =
  'https://raw.githubusercontent.com/hampusborgos/country-flags/main/svg'
const STORAGE_PREFIX = 'bbrf-flag:'
// stored for countrycodes upstream has no flag for
const MISSING = ''

const lookups: Record<string, Promise<string | undefined>> = {}

const readStored = (code: string): string | null => {
  try {
    return localStorage.getItem(STORAGE_PREFIX + code)
  } catch {
    return null
  }
}

const store = (code: string, svg: string) => {
  try {
    localStorage.setItem(STORAGE_PREFIX + code, svg)
  } catch {
    // storage full or blocked: the in-memory lookup still covers this page load
  }
}

const toObjectUrl = (svg: string) =>
  URL.createObjectURL(new Blob([svg], { type: 'image/svg+xml' }))

const lookup = async (code: string): Promise<string | undefined> => {
  const stored = readStored(code)
  if (stored != null) {
    return stored === MISSING ? undefined : toObjectUrl(stored)
  }

  const response = await fetch(`${UPSTREAM}/${code}.svg`)
  if (response.status === 404) {
    store(code, MISSING)
    return undefined
  }
  if (!response.ok) return undefined

  const svg = await response.text()
  store(code, svg)
  return toObjectUrl(svg)
}

export const flagUrl = (countrycode: string): Promise<string | undefined> => {
  const code = countrycode.toLowerCase()
  if (!/^[a-z]{2}$/.test(code)) return Promise.resolve(undefined)

  lookups[code] ??= lookup(code).catch(() => undefined)
  return lookups[code]
}
