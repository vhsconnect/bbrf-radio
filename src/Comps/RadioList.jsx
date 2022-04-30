import React from 'react'
import Radio from './Radio'

const RadioList = ({ channels, setStationController }) => (
  <div>
    {channels.map((x, y) => (
      <Radio
        identifier={`radio-${y}`}
        key={`radio-${y}`}
        info={x}
        setStationController={setStationController}
      />
    ))}
  </div>
)

export default RadioList
