import React from 'react'
import Button from './Button'

const Radio = ({
  info,
  lockStations,
  setStationController,
  setLockStations,
}) => {
  const onClick = () => {
    setStationController(info)
    setLockStations(true)
    fetch('/clicked/' + info.stationuuid).catch(e => console.error(e))
  }

  return (
    <div>
      <Button disabled={lockStations} text={info.name} onClick={onClick} />
    </div>
  )
}

export default Radio
