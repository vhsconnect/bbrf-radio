import { useEffect } from 'react'
import { combineLatest, fromEvent, interval } from 'rxjs'
import { map, startWith, takeWhile } from 'rxjs/operators'
import * as R from 'ramda'
import type { RadioInterface } from '../types'

const ABORT_RADIO_INTERVAL = 5000

interface Props {
  stationController: RadioInterface
  volume: number
  msToVolumeRatio: number
  current: HTMLAudioElement
  last: HTMLAudioElement | undefined
  setLockStations: (x: boolean) => void
  messageUser: (x: string) => void
  setPlayerTitle: (x: string[]) => void
  backtrackCurrentStation: (x: RadioInterface) => void
}

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
}: Props) => {
  useEffect(() => {
    if (stationController.up()) {
      let timeout: number

      const volumeElement = document.getElementById(
        'volume'
      ) as HTMLInputElement | null
      const fromVolume = volumeElement
        ? fromEvent<Event>(volumeElement, 'input').pipe(
            startWith(null),
            map(x => x && (x.target as HTMLInputElement)?.valueAsNumber / 10)
          )
        : fromEvent<Event>([], 'input').pipe(
            startWith(null),
            map(x => x && (x.target as HTMLInputElement)?.valueAsNumber / 10)
          )

      const _fader = interval(msToVolumeRatio / (volume || 1)).pipe(
        map(R.pipe(R.subtract(volume * 100), R.flip(R.divide)(100))),
        takeWhile(R.flip(R.gte)(0))
      )
      const fader = combineLatest([_fader, fromVolume])
      const fromError = fromEvent(current, 'error')
      const errorSub = fromError.subscribe(() => {
        messageUser('faulty station, aborting...')
      })

      const fromPlaying = fromEvent(current, 'playing')

      const fromLoading = fromEvent(current, 'loadstart')

      const loadingSub = fromLoading.subscribe({
        next: () => {
          timeout = setTimeout(() => {
            messageUser('Timed out, aborting...')
            stationController.current.stream.pause()
            backtrackCurrentStation(stationController)
            setLockStations(false)
            playingSub.unsubscribe()
          }, ABORT_RADIO_INTERVAL)
        },
      })

      const playingSub = fromPlaying.subscribe({
        next: () => {
          clearTimeout(timeout)
          setLockStations(false)
          last &&
            fader.subscribe({
              next([x, y]) {
                if (R.pipe(R.isNil, R.not)(y)) {
                  current.volume = y as number
                  last.volume = 0
                  last.pause()
                  return
                }
                last.volume = Number(x)
                current.volume = Number(volume - Number(x))
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

      current.play()

      return () => {
        clearTimeout(timeout)
        playingSub.unsubscribe()
        errorSub.unsubscribe()
        loadingSub.unsubscribe()
      }
    }
  }, [stationController])
}

export default useStationHandler
