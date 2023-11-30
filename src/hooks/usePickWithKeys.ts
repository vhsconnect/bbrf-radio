import { useEffect } from 'react'
import * as R from 'ramda'
import { fromEvent, filter } from 'rxjs'

const usePickWithKeys = ({
  setStationController,
  filteredChannels,
  selector,
  setSelector,
}) => {
  // no scroll
  useEffect(() => {
    document.addEventListener('keydown', e => {
      if (e.key === 'ArrowUp' || e.key === 'ArrowDown') {
        e.preventDefault()
      }
    })
  }, [])

  useEffect(() => {
    const keydown = fromEvent(document, 'keydown')
      .pipe(filter(({ target }) => !(target instanceof HTMLInputElement)))
      .subscribe(
        R.cond([
          [
            e => e.key === 'Enter',
            () => setStationController(filteredChannels[selector]),
          ],
          [
            e => e.key === 'ArrowDown',
            () => setSelector((selector + 1) % filteredChannels.length),
          ],
          [
            e => e.key === 'ArrowUp',
            () =>
              setSelector(
                (selector - 1 + filteredChannels.length) %
                  filteredChannels.length
              ),
          ],
          [R.T, R.identity],
        ])
      )
    return () => keydown.unsubscribe()
  }, [filteredChannels, selector, setSelector])
}

export default usePickWithKeys
