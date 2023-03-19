import React from 'react'
import Button from './Button'
import { combineLatest, fromEvent, interval } from 'rxjs'
import { takeWhile, startWith, map } from 'rxjs/operators'
import * as R from 'ramda'
import Teleprompt from './Teleprompt'

const Player = ({
  stationController,
  backtrackCurrentStation,
  favorites,
  messageUser,
  setLockStations,
  setFavorites,
  msToVolumeRatio,
  setStationController,
}) => {
  const [volume, setVolume] = React.useState(1)
  const [playerTitle, setPlayerTitle] = React.useState([])
  const current = stationController.current?.stream
  const last = stationController.last?.stream
  const isFav = x =>
    R.includes(x.stationuuid)(R.map(R.prop('stationuuid'), favorites))

  // handle change stations
  React.useEffect(() => {
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

  // handle change volume
  React.useEffect(() => {
    if (current) current.volume = volume
  }, [volume])

  return current ? (
    <div className="radio-player">
      <div>
        <Button
          text={'⏮️'}
          disabled={stationController.values.length < 2}
          onClick={() => {
            setLockStations(true)
            setStationController(stationController.last)
          }}
        />
        <Button
          text={'⏯️'}
          onClick={() => {
            current.paused ? current.play() : current.pause()
          }}
        />
      </div>
      <Teleprompt textStack={playerTitle} ms={60} />
      <div>
        <Button
          title="add to favs"
          disabled={isFav(stationController.current)}
          text="🌟"
          onClick={() => {
            fetch(
              '/write/addStation/' + stationController.current.stationuuid,
              {
                method: 'POST',
              }
            )
              .then(data => data.json())
              .then(setFavorites)
          }}
        />
        <Button
          title="remove from favs"
          disabled={!isFav(stationController.current)}
          text="🚮"
          onClick={() => {
            fetch(
              '/write/removeStation/' + stationController.current.stationuuid,
              {
                method: 'POST',
              }
            )
              .then(data => data.json())
              .then(setFavorites)
          }}
        />
      </div>
      <input
        id="volume"
        type="range"
        min={0}
        max={10}
        defaultValue={volume * 10}
        onChange={e => {
          setVolume(e.target.value / 10)
        }}
      />
    </div>
  ) : (
    <div></div>
  )
}
export default Player
