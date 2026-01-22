import React from 'react'
import type { Radio } from '../types'
import Button from './Button'

interface Props {
  deleteCandidate: Radio
  setDeleteCandidate: (x: Radio | null) => void
  removeFromFavorites: (uuid: string) => void
}

const DeleteFaultyStation = ({
  deleteCandidate,
  setDeleteCandidate,
  removeFromFavorites,
}: Props) => {
  return (
    <div style={{ display: 'flex', alignItems: 'center' }}>
      <span style={{ paddingRight: '5px' }}>
        Fetching stream was unsuccessful - delete {deleteCandidate.name} ?
      </span>
      <div style={{ paddingRight: '5px' }}>
        <Button
          disabled={false}
          text="yes"
          onClick={() => {
            removeFromFavorites(deleteCandidate.stationuuid)
            setDeleteCandidate(null)
          }}
        />
      </div>
      <div>
        <Button
          text="no"
          disabled={false}
          onClick={() => {
            setDeleteCandidate(null)
          }}
        />
      </div>
    </div>
  )
}

export default DeleteFaultyStation
