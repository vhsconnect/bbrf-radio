import React, { useState, useEffect } from 'react'
import * as R from 'ramda'
import Button from './Button'
import Teleprompt from './Teleprompt'
import useStationHandler from '../hooks/useStationHandler'
import { request } from '../utils/httpHandlers'

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
            request(
              '/write/addStation/' + stationController.current.stationuuid,
              {
                method: 'POST',
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
          text="🚮"
          onClick={() => {
            request(
              '/write/removeStation/' + stationController.current.stationuuid,
              {
                method: 'POST',
              }
            )
              .then(data => data.json())
              .then(setFavorites)
              .catch(() => messageUser("Couldn't remove favorite"))
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
