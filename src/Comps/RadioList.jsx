import React from 'react'
import Radio from './Radio'

const RadioList = ({ channels, favorites, setStationController }) => (
  <div>
    {channels.map((x, y) => (
      <Radio
        favorites={favorites}
        identifier={`radio-${y}`}
        key={`radio-${y}`}
        info={x}
        setStationController={setStationController}
      />
    ))}
  </div>
)

export default RadioList
