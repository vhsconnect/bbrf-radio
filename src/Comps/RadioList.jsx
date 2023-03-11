import React from 'react'
import Radio from './Radio'

const RadioList = ({
  channels,
  setStationController,
  lockStations,
  isFavsList,
  currentOffset,
  setLockStations,
  setCurrentOffset,
}) => {
  return (
    <div>
      {channels.map((x, y) => (
        <div key={`radio-${y}`} className="flex-div">
          <Radio
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
