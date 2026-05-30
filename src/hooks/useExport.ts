import { useState } from 'react'
import type { Radio, RadioCollection } from '../types'

const STATIC_URL = 'https://bbrf.vhsconnect.link'

export type ExportHandler = {
  toggle: (radio: Radio) => void
  isSelected: (uuid: string) => boolean
}

const useExport = (messageUser: (str: string) => void) => {
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
        const url = `${STATIC_URL}?favorites=${encodeURIComponent(
          JSON.stringify(selectedRadios)
        )}`
        navigator.clipboard.writeText(url)
        messageUser('Copied radios to clipboard')
      }
      setSelectedRadios([])
      setExportMode(false)
    } else {
      setSelectedRadios([])
      setExportMode(true)
      messageUser('Export mode on. Click export again when done ...')
    }
  }

  const exportHandler: ExportHandler | null = exportMode
    ? { toggle, isSelected }
    : null

  return { exportMode, selectedRadios, toggleExportMode, exportHandler }
}

export default useExport
