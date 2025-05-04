import * as R from 'ramda'

export const addFavorite = radioPayload => {
  const searchParams = new URLSearchParams(window.location.search)
  const favorites = R.flip(R.concat)([radioPayload])(getFavorites() ?? [])
  const encodedFavorites = R.pipe(JSON.stringify, encodeURI)(favorites)

  searchParams.set('favorites', encodedFavorites)

  const newUrl = window.location.pathname + '?' + searchParams.toString()
  window.history.pushState({}, '', newUrl)
  return Promise.resolve(favorites)
}

export const removeFavorite = uuid => {
  const searchParams = new URLSearchParams(window.location.search)
  const favorites = R.reject(
    R.propEq('stationuuid', uuid),
    getFavorites() ?? []
  )

  const encodedFavorites = R.pipe(JSON.stringify, encodeURI)(favorites)

  searchParams.set('favorites', encodedFavorites)

  const newUrl = window.location.pathname + '?' + searchParams.toString()
  window.history.pushState({}, '', newUrl)
  return Promise.resolve(favorites)
}

export const getFavorites = () => {
  const searchParams = new URLSearchParams(window.location.search)
  const favorites = searchParams.get('favorites')
  if (favorites) {
    return JSON.parse(decodeURI(favorites))
  }
}
