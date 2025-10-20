import { useEffect } from 'react'
import { buffer, debounceTime, filter, fromEvent } from 'rxjs'
import * as R from 'ramda'

interface Props {
  radioFilter: string
  setRadioFilter: (x: string) => void
  tagsInput: React.RefObject<HTMLInputElement>
  ccInput: React.RefObject<HTMLInputElement>
  nameInput: React.RefObject<HTMLInputElement>
}

const useFilterRadios = ({
  radioFilter,
  setRadioFilter,
  tagsInput,
  ccInput,
  nameInput,
}: Props) => {
  useEffect(() => {
    const viaInputElment = fromEvent(document, 'keydown').pipe(
      filter(({ target }) => target instanceof HTMLInputElement)
    )

    const viaDocument = fromEvent(document, 'keydown').pipe(
      filter(({ target }) => !(target instanceof HTMLInputElement))
    )

    const inputSub = viaInputElment
      .pipe(
        filter(
          (e): e is KeyboardEvent =>
            e instanceof KeyboardEvent &&
            (e.key === 'Escape' || e.key === 'Enter')
        )
      )
      .subscribe(() => {
        tagsInput.current?.blur()
        ccInput.current?.blur()
        nameInput.current?.blur()
      })

    const docSub = viaDocument
      .pipe(buffer(viaDocument.pipe(debounceTime(300))))
      .subscribe(
        R.unless(R.isEmpty, x => {
          if (R.pipe(R.any(R.propEq('Escape', 'key')))(x)) {
            setRadioFilter('')
          } else {
            R.pipe(
              R.filter(R.propSatisfies(R.propEq(1, 'length'), 'key')),
              R.map((x: Record<'key', string>) => x.key),
              R.reduce((acc, each) => acc + each, ''),
              R.pipe(R.concat(radioFilter), setRadioFilter)
            )(x)
          }
        })
      )

    return () => {
      inputSub.unsubscribe()
      docSub.unsubscribe()
    }
  }, [radioFilter])
}

export default useFilterRadios
