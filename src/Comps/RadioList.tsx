import React, { useEffect, useState } from 'react'
import * as R from 'ramda'
import usePickWithKeys from '../hooks/usePickWithKeys'
import useFavLayout from '../hooks/useFavLayout'
import useMediaQuery from '../hooks/useMediaQuery'
import type { RadioCollection, Radio as RadioType } from '../types'
import Radio from './Radio'
import withDraggable from './withDraggable'
import type { Api } from './Main'

const DraggableRadio = withDraggable(Radio, '.favs-grid')

const GRID_MEDIA_QUERY = '(min-width: 768px)'

const metricValue = (metric: string, radio: RadioType) =>
  radio.metrics?.[metric]?.value ?? null

const formatMetric = (value: number | null) =>
  value == null ? 'n/a' : String(Number(value.toFixed(2)))

interface Props {
  channels: RadioCollection
  lockStations: boolean
  setStationController: (x: RadioType) => void
  setLockStations: (x: boolean) => void
  api: Api
  isFavsList: boolean
  currentOffset: number
  setCurrentOffset: (x: number) => void
  radioFilter: string
  sortMetric: string | undefined
  favsGrid: boolean
}

const RadioList = ({
  channels,
  setStationController,
  lockStations,
  isFavsList,
  currentOffset,
  setLockStations,
  setCurrentOffset,
  api,
  radioFilter,
  sortMetric,
  favsGrid,
}: Props) => {
  const [selector, setSelector] = useState(0)

  const activeMetric = isFavsList ? undefined : sortMetric

  const filteredChannels = channels.filter(
    R.pipe(R.prop('name'), R.toLower, R.includes(radioFilter))
  )

  useEffect(() => {
    setSelector(0)
  }, [radioFilter, activeMetric])

  usePickWithKeys({
    setSelector,
    setStationController,
    selector,
    filteredChannels,
    setLockStations,
  })

  const isGrid = useMediaQuery(GRID_MEDIA_QUERY) && isFavsList && favsGrid
  const favLayout = useFavLayout(channels, isGrid)

  return (
    <div
      ref={favLayout.containerRef}
      className={isGrid ? 'favs-grid' : undefined}
      style={isGrid ? { minHeight: `max(60vh, ${favLayout.height}px)` } : {}}
    >
      {filteredChannels.map((x, y) => {
        const radioProps = {
          keyboardSelection: y === selector,
          lockStations,
          identifier: `radio-${x.stationuuid}`,
          observerId: `radio-${x.stationuuid}`,
          info: x,
          setStationController,
          setLockStations,
          paginationTarget: !isFavsList && y === channels.length - 1,
          currentOffset,
          setCurrentOffset,
          api,
          detail:
            activeMetric === undefined
              ? undefined
              : formatMetric(metricValue(activeMetric, x)),
        }

        return (
          <div key={x.stationuuid} className="flex-div">
            {isGrid ? (
              <DraggableRadio
                {...radioProps}
                position={favLayout.positions[x.stationuuid]}
                z={favLayout.positions[x.stationuuid].z}
                onMove={favLayout.move(x.stationuuid)}
              />
            ) : (
              <Radio {...radioProps} />
            )}
          </div>
        )
      })}
    </div>
  )
}
export default RadioList
