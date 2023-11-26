import { useEffect } from 'react'
import { fromEvent, filter } from 'rxjs'
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

    const docSub = viaDocument.subscribe(
      R.ifElse(
        R.propEq('key', 'Escape'),
        () => setRadioFilter(''),
        R.when(
          R.propSatisfies(R.propEq('length', 1), 'key'),
          R.pipe(R.prop('key'), R.concat(radioFilter), setRadioFilter)
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
