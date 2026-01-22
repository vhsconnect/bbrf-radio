import React from 'react'
import { Radio } from '../types'
import Button from './Button'
import withSplashed from './withSplashed'
import type { Api } from './Main'

interface Props {
  info: Radio
  lockStations: boolean
  setStationController: (x: Radio) => void
  setLockStations: (x: boolean) => void
  keyboardSelection: boolean
  api: Api
}

const Radio = ({
  info,
  lockStations,
  setStationController,
  setLockStations,
  keyboardSelection,
  api,
}: Props) => (
  <div className="fade-in">
    <Button
      alternateColor={keyboardSelection}
      disabled={lockStations}
      text={info.name}
      onClick={() => {
        setStationController(info)
        setLockStations(true)
        api.clicked(info.stationuuid)
      }}
    />
  </div>
)

export default withSplashed(Radio)
