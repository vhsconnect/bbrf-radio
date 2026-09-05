const CLOUDFLARE_DNS_JSON = 'https://cloudflare-dns.com/dns-query'
const RADIO_BROWSER_SRV = '_api._tcp.radio-browser.info'

interface DnsJsonResponse {
  Answer?: Array<{ data: string }>
}

// SRV record rdata format: '<priority> <weight> <port> <target>'
// lowest priority wins, the target hostname is the 4th field
const lowestPrioritySrvTarget = (answers: Array<{ data: string }>) => {
  const parsed = answers
    .map(({ data }) => data.split(' '))
    .filter(parts => parts.length === 4 && !Number.isNaN(Number(parts[0])))
    .sort((a, b) => Number(a[0]) - Number(b[0]))

  return parsed[0]?.[3] ?? null
}

// resolve the radio-browser api hostname via a DNS-over-HTTPS SRV lookup.
// never rejects: resolves to null when the lookup fails or is malformed
export const discoverRadioBrowserApiUrl = (): Promise<string | null> =>
  fetch(`${CLOUDFLARE_DNS_JSON}?name=${RADIO_BROWSER_SRV}&type=SRV`, {
    headers: { Accept: 'application/dns-json' },
  })
    .then(response => response.json())
    .then((body: DnsJsonResponse) =>
      lowestPrioritySrvTarget(body?.Answer ?? [])
    )
    .catch(() => null)
