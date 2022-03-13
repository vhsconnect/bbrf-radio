import React from 'react'
import Radio from './Radio'

const RadioList = ({ channels, favorites }) => {
  return (
    <div>
      {channels.map((x, y) => (
        <Radio
          favorites={favorites}
          identifier={`radio-${y}`}
          key={`radio-${y}`}
          info={x}
        />
      ))}
    </div>
  )
}

export default RadioList
