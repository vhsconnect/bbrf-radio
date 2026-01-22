import React, { useEffect, useState } from 'react'
import * as R from 'ramda'
import { Effect } from 'effect'
import useStationHandler from '../hooks/useStationHandler'
import useQueryTrackInfo from '../hooks/useQueryTrackInfo'
import type { Radio, RadioCollection, RadioInterface } from '../types'
import Button from './Button'
import Teleprompt from './Teleprompt'
import type { Api } from './Main'

interface Props {
  stationController: RadioInterface
  backtrackCurrentStation: (x: RadioInterface) => void
  favorites: RadioCollection
  messageUser: (x: string) => void
  defaultMessage: string
  setLockStations: (x: boolean) => void
  setFavorites: (x: RadioCollection) => void
  setStatusStack: (xs: string[]) => void
  setStationController: (x: Radio) => void
  msToVolumeRatio: number
  removeFromFavorites: (uuid: string) => void
  api: Api
}

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
  removeFromFavorites,
  api,
}: Props) => {
  const [volume, setVolume] = useState(1)
  const [playerTitle, setPlayerTitle] = useState<string[]>([])
  const current = stationController.current?.stream
  const last = stationController.last?.stream
  const isFav = (x: Radio) =>
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
    defaultMessage,
    setStatusStack,
  })

  return current ? (
    <div className="radio-player">
      <div>
        <Button
          text={'⏮️'}
          disabled={stationController.values.length < 2}
          onClick={() => {
            if (stationController.last) {
              setLockStations(true)
              stationController.last.stream.load()
              setStationController(stationController.last)
            }
          }}
        />
        <Button
          text={'⏯️'}
          disabled={false}
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
          disabled={isFav(stationController.current)}
          text="🌟"
          onClick={() => {
            Effect.runPromise(
              api.addFavorite(
                R.applySpec({
                  stationuuid: R.path(['current', 'stationuuid']),
                  countrycode: R.either(
                    R.path(['current', 'countrycode']),
                    R.always('none')
                  ),
                  url: R.either(
                    R.path(['current', 'url_resolved']),
                    R.path(['current', 'url'])
                  ),
                  name: R.path(['current', 'name']),
                  bitrate: R.either(
                    R.path(['current', 'bitrate']),
                    R.always(0)
                  ),
                })(stationController)
              )
            )
              .then(setFavorites)
              .catch(() => messageUser("Couldn't add favorite"))
          }}
        />
        <Button
          disabled={!isFav(stationController.current)}
          text="🗑"
          onClick={() =>
            removeFromFavorites(stationController.current.stationuuid)
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
          setVolume(Number(e.target.value) / 10)
        }}
      />
    </div>
  ) : (
    <div></div>
  )
}

export default Player
