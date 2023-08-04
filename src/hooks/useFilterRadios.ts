import { useEffect } from 'react'
import { fromEvent, filter } from 'rxjs'
import * as R from 'ramda'

const useFilterRadios = ({ radioFilter, setRadioFilter }) => {
  useEffect(() => {
    const keydown = fromEvent(document, 'keydown')
      .pipe(filter(({ target }) => !(target instanceof HTMLInputElement)))
      .subscribe(
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
      keydown.unsubscribe()
    }
  }, [radioFilter])
}

export default useFilterRadios
