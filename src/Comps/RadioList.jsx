import React, { useState, useEffect } from 'react'
import Radio from './Radio'
import * as R from 'ramda'
import usePickWithKeys from '../hooks/usePickWithKeys'

const RadioList = ({
  channels,
  setStationController,
  lockStations,
  isFavsList,
  currentOffset,
  setLockStations,
  setCurrentOffset,
  api,
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
    setLockStations,
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
            api={api}
          />
        </div>
      ))}
    </div>
  )
}
export default RadioList
