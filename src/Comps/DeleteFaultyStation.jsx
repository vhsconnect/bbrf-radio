import React from 'react'
import Button from './Button'

const DeleteFaultyStation = ({
  deleteCandidate,
  setDeleteCandidate,
  removeFromFavorites,
}) => {
  return (
    <div style={{ display: 'flex', alignItems: 'center' }}>
      <span style={{ paddingRight: '5px' }}>
        Fetching stream was unsuccessful - delete {deleteCandidate.name} ?
      </span>
      <div style={{ paddingRight: '5px' }}>
        <Button
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
          onClick={() => {
            setDeleteCandidate(null)
          }}
        />
      </div>
    </div>
  )
}

export default DeleteFaultyStation
