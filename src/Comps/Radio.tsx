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
  // shown after the name, e.g. the value the list is sorted by
  detail?: string
}

const Radio = ({
  info,
  lockStations,
  setStationController,
  setLockStations,
  keyboardSelection,
  api,
  detail,
}: Props) => (
  <div className="fade-in">
    <Button
      alternateColor={keyboardSelection}
      disabled={lockStations}
      text={detail === undefined ? info.name : `${info.name} (${detail})`}
      onClick={() => {
        setStationController(info)
        setLockStations(true)
        api.clicked(info.stationuuid)
      }}
    />
  </div>
)

export default withSplashed(Radio)
