class Error5xx extends Error {}

export const handle5xx = (data: Response): Response => {
  if (String(data.status).match(/5\d{2}/)) {
    throw new Error5xx()
  }
  return data
}

export const request = (url: string, options = {}): Promise<unknown> =>
  fetch(url, options)
    .then(handle5xx)
    .then(x => x.json())
