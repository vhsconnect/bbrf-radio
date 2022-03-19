import React from 'react'
import Button from './Button'

const Radio = ({ info, setStationController }) => {
  const onClick = () => {
    setStationController(info)
    fetch('/clicked/' + info.stationuuid).catch(e => console.error(e))
  }

  return (
    <div>
      <Button text={info.name} onClick={onClick} />
    </div>
  )
}

export default Radio
