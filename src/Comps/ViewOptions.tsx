import React from 'react'
import Checkbox from './Checkbox'
import type { Mode } from './Main'

interface Props {
  isFavsView: boolean
  mode: Mode
  favsGrid: boolean
  setFavsGrid: (x: boolean) => void
  metricNames: ReadonlyArray<string>
  sortMetric: string | undefined
  setSortMetric: (x: string | undefined) => void
}

export default function ViewOptions({
  isFavsView,
  mode,
  favsGrid,
  setFavsGrid,
  metricNames,
  sortMetric,
  setSortMetric,
}: Props) {
  if (isFavsView) {
    return (
      <div className="view-options">
        <Checkbox
          text="grid"
          title="arrange favorites on a draggable grid"
          checked={favsGrid}
          onChange={setFavsGrid}
        />
      </div>
    )
  }

  if (metricNames.length === 0) return null

  return (
    <div className="view-options">
      {metricNames.map(metric => (
        <Checkbox
          key={metric}
          text={metric}
          title={`sort by ${metric}`}
          checked={metric === sortMetric}
          disabled={mode !== 'radio'}
          onChange={checked => setSortMetric(checked ? metric : undefined)}
        />
      ))}
    </div>
  )
}
