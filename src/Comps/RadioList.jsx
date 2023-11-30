import React, { useState } from 'react'
import Radio from './Radio'
import * as R from 'ramda'
import usePickWithKeys from '../hooks/usePickWithKeys'
import { useEffect } from 'react'

const RadioList = ({
  channels,
  setStationController,
  lockStations,
  isFavsList,
  currentOffset,
  setLockStations,
  setCurrentOffset,
  radioFilter,
}) => {
  const [selector, setSelector] = useState(0)
  const filteredChannels = channels.filter(
    R.pipe(R.prop('name'), R.toLower, R.includes(radioFilter))
  )

  useEffect(() => {
    setSelector(0)
  }, [radioFilter])

  usePickWithKeys({
    setSelector,
    setStationController,
    selector,
    filteredChannels,
  })

  return (
    <div>
      {filteredChannels.map((x, y) => (
        <div key={`radio-${y}`} className="flex-div">
          <Radio
            keyboardSelection={y === selector}
            lockStations={lockStations}
            identifier={`radio-${y}`}
            observerId={`radio-${y}`}
            info={x}
            setStationController={setStationController}
            setLockStations={setLockStations}
            paginationTarget={!isFavsList && y === channels.length - 1}
            currentOffset={currentOffset}
            setCurrentOffset={setCurrentOffset}
          />
        </div>
      ))}
    </div>
  )
}
export default RadioList
