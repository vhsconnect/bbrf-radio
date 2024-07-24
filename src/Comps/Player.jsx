import React, { useState, useEffect } from 'react'
import * as R from 'ramda'
import Button from './Button'
import Teleprompt from './Teleprompt'
import useStationHandler from '../hooks/useStationHandler'
import useQueryTrackInfo from '../hooks/useQueryTrackInfo'
import { request } from '../utils/httpHandlers'

const Player = ({
  stationController,
  backtrackCurrentStation,
  favorites,
  messageUser,
  defaultMessage,
  setLockStations,
  setFavorites,
  setStatusStack,
  setStationController,
  msToVolumeRatio,
    removeFromFavorites
}) => {
  const [volume, setVolume] = useState(1)
  const [playerTitle, setPlayerTitle] = useState([])
  const current = stationController.current?.stream
  const last = stationController.last?.stream
  const isFav = x =>
    R.includes(x.stationuuid)(R.map(R.prop('stationuuid'), favorites))

  useStationHandler({
    stationController,
    volume,
    msToVolumeRatio,
    current,
    last,
    setLockStations,
    messageUser,
    setPlayerTitle,
    backtrackCurrentStation,
  })

  useEffect(() => {
    if (current) current.volume = volume
  }, [volume])

  useQueryTrackInfo({
    stationController,
    current,
    setStatusStack,
    defaultMessage,
  })

  return current ? (
    <div className="radio-player">
      <div>
        <Button
          text={'⏮️'}
          disabled={stationController.values.length < 2}
          onClick={() => {
            setLockStations(true)
            stationController.last.stream.load()
            setStationController(stationController.last)
          }}
        />
        <Button
          text={'⏯️'}
          onClick={() => {
            if (current.paused) {
              current.load()
              current.play()
            } else current.pause()
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
            request(
              R.pipe(
                R.map(x => x(stationController)),
                R.join('/')
              )([
                R.always('/write/addStation'),
                R.path(['current', 'stationuuid']),
              ]),
              {
                method: 'POST',
                body: R.pipe(
                  R.applySpec({
                    countrycode: R.either(
                      R.path(['current', 'countrycode']),
                      R.always('none')
                    ),
                    url: R.path(['current', 'url_resolved']),
                    name: R.path(['current', 'name']),
                    bitrate: R.either(
                      R.path(['current', 'bitrate']),
                      R.always(0)
                    ),
                  }),
                  JSON.stringify
                )(stationController),
              }
            )
              .then(data => data.json())
              .then(setFavorites)
              .catch(() => messageUser("Couldn't add favorite"))
          }}
        />
        <Button
          title="remove from favs"
          disabled={!isFav(stationController.current)}
          text="🗑"
          onClick={() => removeFromFavorites(stationController.current.stationuuid)
          }
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
