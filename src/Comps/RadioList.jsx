import React from 'react'
import Radio from './Radio'
import * as R from 'ramda'
import Button from './Button'
import { toUnixTimestamp } from '../utils/easyDate'

const RadioList = ({
  channels,
  setStationController,
  lockStations,
  targetEasyDate,
  favorites,
  setFavorites,
}) => {
  return (
    <div>
      {channels.map((x, y) => (
        <div key={`radio-${y}`} className="flex-div">
          <Radio
            lockStations={lockStations}
            identifier={`radio-${y}`}
            info={x}
            setStationController={setStationController}
          />
          <Button
            title="schedule"
            disabled={
              !R.includes(x.stationuuid)(R.pluck('stationuuid', favorites))
            }
            text="⏱"
            onClick={() => {
              fetch(
                '/write/schedule/' +
                  x.stationuuid +
                  '/' +
                  toUnixTimestamp(new Date(targetEasyDate)),
                {
                  method: 'PUT',
                }
              )
                .then(data => data.json())
                .then(setFavorites)
            }}
          />
        </div>
      ))}
    </div>
  )
}
export default RadioList
