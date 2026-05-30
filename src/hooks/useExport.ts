import { useState } from 'react'
import type { Radio, RadioCollection } from '../types'

export type ExportHandler = {
  toggle: (radio: Radio) => void
  isSelected: (uuid: string) => boolean
}

const useExport = () => {
  const [exportMode, setExportMode] = useState(false)
  const [selectedRadios, setSelectedRadios] = useState<RadioCollection>([])

  const toggle = (radio: Radio) => {
    setSelectedRadios(prev =>
      prev.some(x => x.stationuuid === radio.stationuuid)
        ? prev.filter(x => x.stationuuid !== radio.stationuuid)
        : [...prev, radio]
    )
  }

  const isSelected = (uuid: string) =>
    selectedRadios.some(x => x.stationuuid === uuid)

  const toggleExportMode = () => {
    if (exportMode) {
      if (selectedRadios.length > 0) {
        const url = `https://bbrf.vhsconnect.link?favorites=${encodeURIComponent(
          JSON.stringify(selectedRadios)
        )}`
        navigator.clipboard.writeText(url)
      }
      setSelectedRadios([])
      setExportMode(false)
    } else {
      setSelectedRadios([])
      setExportMode(true)
    }
  }

  const exportHandler: ExportHandler | null = exportMode
    ? { toggle, isSelected }
    : null

  return { exportMode, selectedRadios, toggleExportMode, exportHandler }
}

export default useExport
