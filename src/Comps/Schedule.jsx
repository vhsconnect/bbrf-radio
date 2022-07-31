import React from 'react'
import * as R from 'ramda'
import { toHumanReadableDate } from '../utils/easyDate'
import Button from './Button'

export default function Schedule({ favorites, setFavorites }) {
  const timings = favorites
    .filter(R.prop('scheduled'))
    .sort((a, b) => a.scheduled - b.scheduled)
    .map((x, y) => (
      <ol
        style={{ display: 'flex', paddingBottom: '10px' }}
        key={'schedule' + y}
      >
        <>
          {x.name}: {toHumanReadableDate(x.scheduled)}
        </>
        <div style={{ paddingLeft: '10px' }}>
          <Button
            text="🚮"
            onClick={() =>
              fetch('/write/remove-schedule/' + x.stationuuid, {
                method: 'PUT',
              })
                .then(data => data.json())
                .then(setFavorites)
            }
          />
        </div>
      </ol>
    ))
  return (
    <div>
      <ul>{timings}</ul>
    </div>
  )
}
