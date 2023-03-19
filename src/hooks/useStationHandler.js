import { useEffect } from 'react'
import { combineLatest, fromEvent, interval } from 'rxjs'
import { takeWhile, startWith, map } from 'rxjs/operators'
import * as R from 'ramda'

const useStationHandler = ({
  stationController,
  volume,
  msToVolumeRatio,
  current,
  last,
  setLockStations,
  messageUser,
  setPlayerTitle,
  backtrackCurrentStation,
}) => {
  useEffect(() => {
    if (stationController.up()) {
      const fromVolume = fromEvent(
        document.getElementById('volume'),
        'input'
      ).pipe(
        startWith(null),
        map(x => x && x.target.valueAsNumber / 10)
      )
      const _fader = interval(msToVolumeRatio / (volume || 1)).pipe(
        map(R.pipe(R.subtract(volume * 100), R.flip(R.divide)(100))),
        takeWhile(R.flip(R.gte)(0))
      )
      const fader = combineLatest([_fader, fromVolume])
      const fromError = fromEvent(current, 'error')
      fromError.subscribe(() => {
        setLockStations(false)
        messageUser('faulty station - try this one later')
      })

      const fromPlaying = fromEvent(current, 'playing')
      fromPlaying.subscribe({
        next: () => {
          setLockStations(false)
          last &&
            fader.subscribe({
              next([x, y]) {
                if (R.pipe(R.isNil, R.not)(y)) {
                  current.volume = y
                  last.volume = 0
                  last.pause()
                  return
                }
                last.volume = x
                current.volume = volume - x
                x === 0 ? last.pause() : null
              },
              complete() {
                last.pause()
              },
            })

          setPlayerTitle([
            stationController.current.name +
              ' @ ' +
              stationController.current.bitrate,
          ])
        },
      })
      current.play().catch(backtrackCurrentStation)
    }
  }, [stationController])
}

export default useStationHandler
