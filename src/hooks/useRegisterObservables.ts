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
  setFavorites: (xs: Readonly<Radio[]>) => void
  setChannels: (xs: Readonly<Radio[]>) => void
  messageUser: (x: string) => void
  api: Api
}

export default ({
  setTag,
  setCountrycode,
  setName,
  setFavorites,
  setChannels,
  messageUser,
  api,
}: Props) => {
  useEffect(() => {
    const tagsObservable = fromEvent(
      document.getElementById('tags') as HTMLInputElement,
      'input'
    )
    const ccObservable = fromEvent(
      document.getElementById('countrycode') as HTMLInputElement,
      'input'
    )
    const nameObservable = fromEvent(
      document.getElementById('name') as HTMLInputElement,
      'input'
    )

    tagsObservable
      .pipe(debounceTime(1000))
      .subscribe(e => setTag((e.target as HTMLInputElement).value))

    ccObservable
      .pipe(debounceTime(1000))
      .subscribe(e => setCountrycode((e.target as HTMLInputElement).value))

    nameObservable
      .pipe(debounceTime(1000))
      .subscribe(e => setName((e.target as HTMLInputElement).value))

    const s1 = tagsObservable.subscribe(() => {
      const countrycode = document.getElementById(
        'countrycode'
      ) as HTMLInputElement
      const name = document.getElementById('name') as HTMLInputElement
      name.value = ''
      countrycode.value = ''
      setCountrycode('')
      setName('')
    })
    const s2 = ccObservable.subscribe(() => {
      const tags = document.getElementById('tags') as HTMLInputElement
      const name = document.getElementById('name') as HTMLInputElement
      name.value = ''
      tags.value = ''
      setTag('')
      setName('')
    })
    const s3 = nameObservable.subscribe(() => {
      const tags = document.getElementById('tags') as HTMLInputElement
      const countrycode = document.getElementById(
        'countrycode'
      ) as HTMLInputElement
      tags.value = ''
      countrycode.value = ''
      setTag('')
      setCountrycode('')
    })

    Effect.runPromise(api.favorites())
      .then(R.tap(setFavorites))
      .then(setChannels)
      .catch(() => {
        messageUser("Couldn't fetch favorites")
      })

    return () => {
      s1.unsubscribe()
      s2.unsubscribe()
      s3.unsubscribe()
    }
  }, [])
}
