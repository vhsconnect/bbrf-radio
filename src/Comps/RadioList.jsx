import React from 'react'
import Radio2 from './Radio2'

const RadioList = ({ channels, favorites, setCurrentStation }) => (
  <div>
    {channels.map((x, y) => (
      <Radio2
        favorites={favorites}
        identifier={`radio-${y}`}
        key={`radio-${y}`}
        info={x}
        setCurrentStation={setCurrentStation}
      />
    ))}
  </div>
)

export default RadioList
