import * as R from 'ramda'
import type { Radio, RadioCollection } from '../types'

export const addFavorite = (radioPayload: Radio): Promise<RadioCollection> => {
  const searchParams = new URLSearchParams(window.location.search)
  const favorites: RadioCollection = R.concat(getFavorites() ?? [], [
    radioPayload,
  ])
  const encodedFavorites = R.pipe(JSON.stringify, encodeURI)(favorites)

  searchParams.set('favorites', encodedFavorites)

  const newUrl = window.location.pathname + '?' + searchParams.toString()
  window.history.pushState({}, '', newUrl)
  return Promise.resolve(favorites)
}

export const removeFavorite = (uuid: string): Promise<RadioCollection> => {
  const searchParams = new URLSearchParams(window.location.search)
  const favorites = R.reject<Radio>((x: Radio) => x.stationuuid === uuid)(
    getFavorites() ?? []
  )

  const encodedFavorites = R.pipe(JSON.stringify, encodeURI)(favorites)

  searchParams.set('favorites', encodedFavorites)

  const newUrl = window.location.pathname + '?' + searchParams.toString()
  window.history.pushState({}, '', newUrl)
  return Promise.resolve(favorites)
}

export const getFavorites = (): RadioCollection | undefined => {
  const searchParams = new URLSearchParams(window.location.search)
  const favorites = searchParams.get('favorites')
  if (favorites) {
    return JSON.parse(decodeURI(favorites))
  }
}
