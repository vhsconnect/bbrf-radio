import { useEffect } from 'react'
import { fromEvent } from 'rxjs'
import { debounceTime } from 'rxjs/operators'
import * as R from 'ramda'
import { Effect } from 'effect'
import type { Radio } from '../types'
import type { Api } from '../Comps/Main'

interface Props {
  setTag: (x: string) => void
  setName: (x: string) => void
  setCountrycode: (x: string) => void
  setTrack: (x: string) => void
  setFavorites: (xs: Readonly<Radio[]>) => void
  setChannels: (xs: Readonly<Radio[]>) => void
  messageUser: (x: string) => void
  api: Api
}

export default ({
  setTag,
  setCountrycode,
  setName,
  setTrack,
  setFavorites,
  setChannels,
  messageUser,
  api,
}: Props) => {
  useEffect(() => {
    const fields = [
      { id: 'tags', set: setTag },
      { id: 'countrycode', set: setCountrycode },
      { id: 'name', set: setName },
      { id: 'track', set: setTrack },
    ] as const

    // the track input only renders in server mode
    const rendered = fields.flatMap(({ id, set }) => {
      const input = document.getElementById(id)
      return input instanceof HTMLInputElement ? [{ input, set }] : []
    })

    const subscriptions = rendered.flatMap(({ input, set }) => {
      const typed = fromEvent(input, 'input')
      return [
        typed.pipe(debounceTime(1000)).subscribe(() => set(input.value)),
        typed.subscribe(() =>
          rendered
            .filter(other => other.input !== input)
            .forEach(other => {
              other.input.value = ''
              other.set('')
            })
        ),
      ]
    })

    Effect.runPromise(api.favorites())
      .then(R.tap(setFavorites))
      .then(setChannels)
      .catch(() => {
        messageUser("Couldn't fetch favorites")
      })

    return () =>
      subscriptions.forEach(subscription => subscription.unsubscribe())
  }, [])
}
