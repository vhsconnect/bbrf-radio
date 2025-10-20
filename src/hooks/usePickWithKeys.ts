import { useEffect } from 'react'
import * as R from 'ramda'
import { filter, fromEvent } from 'rxjs'
import type { Radio, RadioCollection } from '../types';

interface Props {
  setStationController: (x: Radio) => void
  filteredChannels: RadioCollection
  selector: number
  setSelector: (x: number) => void
  setLockStations: (x: boolean) => void
}

const usePickWithKeys = ({
  setStationController,
  filteredChannels,
  selector,
  setSelector,
  setLockStations,
}: Props) => {
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
            () => {
              setStationController(filteredChannels[selector])
              setLockStations(true)
            },
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
