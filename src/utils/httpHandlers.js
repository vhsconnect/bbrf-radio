class Error5xx extends Error {
  constructor(message) {
    super(message)
  }
}

export const handle5xx = data => {
  if (String(data.status).match(/5\d{2}/)) {
    throw new Error5xx()
  }
  return data
}

export const request = (url, options = {}) =>
  fetch(url, options)
    .then(handle5xx)
    .then(x => x.json())
