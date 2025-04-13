import React from 'react'
import Button from './Button'
import withSplashed from './withSplashed'

const Radio = ({
  info,
  lockStations,
  setStationController,
  setLockStations,
  keyboardSelection,
  api,
}) => (
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
