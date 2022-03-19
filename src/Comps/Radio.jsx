import React from 'react'
import Button from './Button'
import * as R from 'ramda'
import { fromEvent } from 'rxjs'

const Radio = ({ info, favorites, identifier }) => {
  React.useEffect(() => {
    fromEvent(
      document.getElementById(`radio-player-${identifier}`),
      'playing'
    ).subscribe(() =>
      fetch('/clicked/' + info.stationuuid).catch(e => console.error(e))
    )
  }, [])

  const isFav = R.includes(info.stationuuid)(
    R.map(R.prop('stationuuid'), favorites)
  )
  return (
    <div>
      <p>{info.name}</p>
      <div className="flex">
        <audio
          id={`radio-player-${identifier}`}
          src={info['url_resolved']}
          preload="none"
          controls
        >
          browser issues?
        </audio>
        <div>
          <Button
            disabled={isFav}
            text="🌟"
            onClick={() => {
              fetch('/write/addStation/' + info.stationuuid, {
                method: 'POST',
              })
            }}
          />
          <Button
            disabled={!isFav}
            text="🚮"
            onClick={() => {
              fetch('/write/removeStation/' + info.stationuuid, {
                method: 'POST',
              })
            }}
          />
        </div>
      </div>
    </div>
  )
}

export default Radio
