import React from 'react'
import Button from './Button'

const Radio2 = ({ info, setCurrentStation  }) => {

  const onClick = () => {
    setCurrentStation(info)
    fetch('/clicked/' + info.stationuuid).catch(e => console.error(e))
  }

  return (
    <div>
      <Button text={info.name} onClick={onClick} />
    </div>
  )
}

export default Radio2
