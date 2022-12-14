import React from 'react'
import Button from './Button'
import { fromEvent, interval } from 'rxjs'
import { takeWhile, map, delay } from 'rxjs/operators'
import * as R from 'ramda'
import Teleprompt from './Teleprompt'
const MS_TO_VOLUME_RATIO = 25

const Player = ({
  stationController,
  backtrackCurrentStation,
  favorites,
  messageUser,
  setLockStations,
  setFavorites,
}) => {
  const [volume, setVolume] = React.useState(1)
  const [playerTitle, setPlayerTitle] = React.useState([])
  const current = stationController.current?.stream
  const last = stationController.last?.stream
  const isFav = x =>
    R.includes(x.stationuuid)(R.map(R.prop('stationuuid'), favorites))
  const withDelay = last && stationController.current.with20delay
  const fader = interval(MS_TO_VOLUME_RATIO / (volume || 1)).pipe(
    map(R.pipe(R.subtract(volume * 100), R.flip(R.divide)(100))),
    takeWhile(R.flip(R.gte)(0)),
    R.when(() => withDelay, delay(20000)) //delay logic
  )

  // handle change stations
  React.useEffect(() => {
    if (stationController.up()) {
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
              next(x) {
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
      <Button
        text="???"
        onClick={() => {
          current.paused ? current.play() : current.pause()
        }}
      />
      <Teleprompt textStack={playerTitle} ms={60} />
      <div>
        <Button
          title="add to favs"
          disabled={isFav(stationController.current)}
          text="????"
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
          text="????"
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
