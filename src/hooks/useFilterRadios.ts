import { useEffect } from 'react'
import {
  fromEvent,
  filter,
  Subject,
  bufferTime,
  debounceTime,
  buffer,
} from 'rxjs'
import * as R from 'ramda'

const useFilterRadios = ({
  radioFilter,
  setRadioFilter,
  tagsInput,
  ccInput,
  nameInput,
}) => {
  useEffect(() => {
    const viaInputElment = fromEvent(document, 'keydown').pipe(
      filter(({ target }) => target instanceof HTMLInputElement)
    )

    const viaDocument = fromEvent(document, 'keydown').pipe(
      filter(({ target }) => !(target instanceof HTMLInputElement))
    )

    const inputSub = viaInputElment.subscribe(
      R.when(
        R.either(R.propEq('key', 'Escape'), R.propEq('key', 'Enter')),
        () => {
          tagsInput.current.blur()
          ccInput.current.blur()
          nameInput.current.blur()
        }
      )
    )

    const docSub = viaDocument
      .pipe(buffer(viaDocument.pipe(debounceTime(300))))
      .subscribe(
        R.unless(
          R.isEmpty,
          R.ifElse(
            R.pipe(R.any(R.propEq('key', 'Escape'))),
            () => setRadioFilter(''),
            R.pipe(
              R.tap(console.log),
              R.filter(R.propSatisfies(R.propEq('length', 1), 'key')),
              R.reduce((acc, each) => acc + each.key, ''),
              R.tap(console.log),
              R.pipe(R.concat(radioFilter), setRadioFilter)
            )
          )
        )
      )

    return () => {
      inputSub.unsubscribe()
      docSub.unsubscribe()
    }
  }, [radioFilter])
}

export default useFilterRadios
