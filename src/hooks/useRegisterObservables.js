import { useEffect } from 'react'
import { fromEvent } from 'rxjs'
import { debounceTime } from 'rxjs/operators'
import * as R from 'ramda'

export default ({ setTag, setCountrycode, setName, setFavorites , setChannels}) => {
  useEffect(() => {
    const tagsObservable = fromEvent(document.getElementById('tags'), 'input')
    const ccObservable = fromEvent(
      document.getElementById('countrycode'),
      'input'
    )
    const nameObservable = fromEvent(document.getElementById('name'), 'input')

    tagsObservable
      .pipe(debounceTime(1000))
      .subscribe(e => setTag(e.target.value))

    ccObservable
      .pipe(debounceTime(1000))
      .subscribe(e => setCountrycode(e.target.value))

    nameObservable
      .pipe(debounceTime(1000))
      .subscribe(e => setName(e.target.value))

    const s1 = tagsObservable.subscribe(() => {
      document.getElementById('countrycode').value = ''
      document.getElementById('name').value = ''
      setCountrycode('')
      setName('')
    })
    const s2 = ccObservable.subscribe(() => {
      document.getElementById('tags').value = ''
      document.getElementById('name').value = ''
      setTag('')
      setName('')
    })
    const s3 = nameObservable.subscribe(() => {
      document.getElementById('tags').value = ''
      document.getElementById('countrycode').value = ''
      setTag('')
      setCountrycode('')
    })

    fetch('/favorites')
      .then(data => data.json())
      .then(R.tap(setFavorites))
      .then(setChannels)

    return () => {
      s1.unsubscribe()
      s2.unsubscribe()
      s3.unsubscribe()
    }
  }, [])
}
