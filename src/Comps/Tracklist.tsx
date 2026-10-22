import React from 'react'
import type { Radio, Track, Tracklisting } from '../types'
import Button from './Button'
import Flag from './Flag'
import type { Api } from './Main'

interface Props {
  tracks: Tracklisting
  lockStations: boolean
  setStationController: (x: Radio) => void
  setLockStations: (x: boolean) => void
  radioFilter: string
  api: Api
}

const trackName = (track: Track) =>
  track.artist && track.title
    ? `${track.artist} – ${track.title}`
    : track.raw_title ?? 'unknown track'

const playedAt = (track: Track) =>
  track.observed_at.toLocaleTimeString([], {
    hour: '2-digit',
    minute: '2-digit',
  })

const Tracklist = ({
  tracks,
  lockStations,
  setStationController,
  setLockStations,
  radioFilter,
  api,
}: Props) => {
  const filteredTracks = tracks.filter(track =>
    `${trackName(track)} ${track.station.name}`
      .toLowerCase()
      .includes(radioFilter)
  )

  return (
    <table className="tracklist">
      <thead>
        <tr>
          <th>played</th>
          <th>track</th>
          <th>station</th>
          <th className="mobile-hidden">country</th>
          <th>tags</th>
        </tr>
      </thead>
      <tbody>
        {filteredTracks.map(track => (
          <tr key={track.id} className="fade-in">
            <td className="tracklist-time">{playedAt(track)}</td>
            <td>{trackName(track)}</td>
            <td className="tracklist-station">
              <Button
                disabled={lockStations}
                text={track.station.name}
                onClick={() => {
                  setStationController(track.station)
                  setLockStations(true)
                  api.clicked(track.station.stationuuid)
                }}
              />
            </td>
            <td className="mobile-hidden">
              <Flag
                countrycode={track.station.countrycode}
                className="flag-small"
              />
            </td>
            <td className="tracklist-tags">{track.station.tags.join(', ')}</td>
          </tr>
        ))}
      </tbody>
    </table>
  )
}

export default Tracklist
