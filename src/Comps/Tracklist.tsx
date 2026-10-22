import React from 'react'
import type { Radio, Track, TrackSort, Tracklisting } from '../types'
import Button from './Button'
import Flag from './Flag'
import withSplashed from './withSplashed'
import type { Api } from './Main'

interface Props {
  tracks: Tracklisting
  sort: TrackSort
  setSort: (sort: TrackSort) => void
  currentOffset: number
  setCurrentOffset: (offset: number) => void
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

const FIRST_DIRECTION = {
  played: 'desc',
  country: 'asc',
} as const satisfies Record<TrackSort['column'], TrackSort['dir']>

const nextSort = (sort: TrackSort, column: TrackSort['column']): TrackSort =>
  sort.column === column
    ? { column, dir: sort.dir === 'asc' ? 'desc' : 'asc' }
    : { column, dir: FIRST_DIRECTION[column] }

interface SortHeaderProps {
  column: TrackSort['column']
  sort: TrackSort
  setSort: (sort: TrackSort) => void
  className?: string
}

const SortHeader = ({ column, sort, setSort, className }: SortHeaderProps) => {
  const active = sort.column === column
  return (
    <th
      className={className}
      aria-sort={
        active ? (sort.dir === 'asc' ? 'ascending' : 'descending') : undefined
      }
    >
      <button
        className="sort-header"
        onClick={() => setSort(nextSort(sort, column))}
      >
        {column}
        {active ? (sort.dir === 'asc' ? ' ▲' : ' ▼') : ''}
      </button>
    </th>
  )
}

const NextPageTarget = withSplashed(() => <div className="tracklist-end" />)

const Tracklist = ({
  tracks,
  sort,
  setSort,
  currentOffset,
  setCurrentOffset,
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
    <div className="tracklist">
      <table>
        <thead>
          <tr>
            <SortHeader column="played" sort={sort} setSort={setSort} />
            <th>track</th>
            <th>station</th>
            <SortHeader
              column="country"
              sort={sort}
              setSort={setSort}
              className="mobile-hidden"
            />
            <th>tags</th>
          </tr>
        </thead>
        <tbody>
          {filteredTracks.map(track => (
            <tr key={track.id} className="fade-in">
              <td className="tracklist-time">{playedAt(track)}</td>
              <td className="tracklist-track" title={trackName(track)}>
                <span>{trackName(track)}</span>
              </td>
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
              <td
                className="tracklist-tags"
                title={track.station.tags.join(', ')}
              >
                <span>{track.station.tags.join(', ')}</span>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
      <NextPageTarget
        observerId="tracklist-end"
        info={tracks.length}
        paginationTarget={tracks.length > 0}
        currentOffset={currentOffset}
        setCurrentOffset={setCurrentOffset}
      />
    </div>
  )
}

export default Tracklist
