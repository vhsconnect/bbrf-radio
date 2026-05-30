import React from 'react'
import { Radio } from '../types'
import Button from './Button'
import withSplashed from './withSplashed'
import type { Api } from './Main'
import type { ExportHandler } from '../hooks/useExport'

interface Props {
  info: Radio
  lockStations: boolean
  setStationController: (x: Radio) => void
  setLockStations: (x: boolean) => void
  keyboardSelection: boolean
  api: Api
  exportHandler: ExportHandler | null
}

const Radio = ({
  info,
  lockStations,
  setStationController,
  setLockStations,
  keyboardSelection,
  api,
  exportHandler,
}: Props) => {
  const isInExportMode = exportHandler !== null
  const isExportSelected =
    isInExportMode && exportHandler.isSelected(info.stationuuid)

  const handleClick = isInExportMode
    ? () => exportHandler.toggle(info)
    : () => {
        setStationController(info)
        setLockStations(true)
        api.clicked(info.stationuuid)
      }

  const alternateColor = isExportSelected
    ? 'orange'
    : keyboardSelection
    ? true
    : false

  return (
    <div className="fade-in">
      <Button
        alternateColor={alternateColor}
        disabled={!isInExportMode && lockStations}
        text={info.name}
        onClick={handleClick}
      />
    </div>
  )
}

export default withSplashed(Radio)
