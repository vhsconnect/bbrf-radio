import { useEffect } from 'react'
import {  combineLatest, fromEvent, interval } from 'rxjs'
import { map, startWith, takeWhile } from 'rxjs/operators'
import * as R from 'ramda'
import type { RadioInterface } from '../types'
import { createLogger } from '../utils/debug'

const log = createLogger('handler')

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
    if (stationController.current) {
      let timeout: number
      const stationName = stationController.current.name

      log.info('station changed', {
        name: stationName,
        hasPrevious: !!last,
        volume,
        msToVolumeRatio,
      })

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
        const err = (current as HTMLAudioElement & { error?: MediaError }).error
        log.error('stream error', {
          name: stationName,
          code: err?.code,
          message: err?.message,
        })
        clearTimeout(timeout)
        messageUser('faulty station, aborting...')
        stationController.current.stream.pause()
        backtrackCurrentStation(stationController)
        setLockStations(false)
        playingSub.unsubscribe()
      })

      const fromPlaying = fromEvent(current, 'playing')

      const fromLoading = fromEvent(current, 'loadstart')

      const loadingSub = fromLoading.subscribe({
        next: () => {
          log.debug('loadstart', { name: stationName })
          timeout = setTimeout(() => {
            log.warn('timeout waiting for playback', {
              name: stationName,
              waitedMs: ABORT_RADIO_INTERVAL,
            })
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
          log.info('playing', { name: stationName, crossfade: !!last })
          setLockStations(false)
          if (last) {
            fader.subscribe({
              next([x, y]) {
                if (R.pipe(R.isNil, R.not)(y)) {
                  log.debug('crossfade interrupted by volume slider', {
                    name: stationName,
                    sliderVolume: y,
                  })
                  current.volume = y as number
                  last.volume = 0
                  last.pause()
                  return
                }
                log.debug('crossfade step', {
                  name: stationName,
                  oldVol: Number(x),
                  newVol: Number(volume - Number(x)),
                })
                last.volume = Number(x)
                current.volume = Number(volume - Number(x))
                x === 0 ? last.pause() : null
              },
              complete() {
                log.info('crossfade complete', { name: stationName })
                last.pause()
              },
            })
          }

          setPlayerTitle([
            stationController.current.name +
              ' @ ' +
              stationController.current.bitrate,
          ])
        },
      })

      log.info('calling play()', { name: stationName, src: current.src })
      current.play()

      return () => {
        log.debug('cleanup subscriptions', { name: stationName })
        clearTimeout(timeout)
        playingSub.unsubscribe()
        errorSub.unsubscribe()
        loadingSub.unsubscribe()
      }
    }
  }, [stationController])
}

export default useStationHandler
