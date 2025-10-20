import React, { useEffect, useState } from 'react'
import * as R from 'ramda'
import usePickWithKeys from '../hooks/usePickWithKeys'
import type { RadioCollection, Radio as RadioType } from '../types'
import Radio from './Radio'
import type { Api } from './Main'

interface Props {
  channels: RadioCollection
  lockStations: boolean
  setStationController: (x: RadioType) => void
  setLockStations: (x: boolean) => void
  api: Api
  isFavsList: boolean
  currentOffset: number
  setCurrentOffset: (x: number) => void
  radioFilter: string
}

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
}: Props) => {
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
