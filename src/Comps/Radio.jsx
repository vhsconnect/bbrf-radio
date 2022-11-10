import React from 'react'
import Button from './Button'
import withSplashed from './withSplashed'

const Radio = ({
  info,
  lockStations,
  setStationController,
  setLockStations,
}) => (
  <div>
    <Button
      disabled={lockStations}
      text={info.name}
      onClick={() => {
        setStationController(info)
        setLockStations(true)
        fetch('/clicked/' + info.stationuuid).catch(e => console.error(e))
      }}
    />
  </div>
)

export default withSplashed(Radio)
