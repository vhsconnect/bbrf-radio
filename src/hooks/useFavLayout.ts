import { useLayoutEffect, useRef, useState } from 'react'
import * as R from 'ramda'
import type { RadioCollection } from '../types'
import { GRID_CELL } from '../Comps/withDraggable'
import type { FavLayout, Placement, Position } from '../utils/favLayout'
import { loadLayout, placeStations, saveLayout } from '../utils/favLayout'

const CELL_WIDTH = GRID_CELL * 12
const CELL_HEIGHT = GRID_CELL * 3
const SPARE_ROWS = 3

const snap = (n: number) => Math.max(0, Math.round(n / GRID_CELL) * GRID_CELL)

const highest = (key: 'y' | 'z', placements: Placement[]) =>
  R.reduce(R.max<number>, 0, R.map(R.prop(key), placements))

const useFavLayout = (channels: RadioCollection, enabled: boolean) => {
  const containerRef = useRef<HTMLDivElement>(null)
  const [layout, setLayout] = useState<FavLayout>(loadLayout)
  const [width, setWidth] = useState(0)

  useLayoutEffect(() => {
    const container = containerRef.current
    if (!container) return
    const measure = () => setWidth(container.clientWidth)
    measure()
    const observer = new ResizeObserver(measure)
    observer.observe(container)
    return () => observer.disconnect()
  }, [])

  // stations saved on a wider window are pulled back into view
  const maxX = Math.max(
    0,
    Math.floor((width - CELL_WIDTH) / GRID_CELL) * GRID_CELL
  )

  const positions: FavLayout = enabled
    ? R.map(
        p => ({ ...p, x: Math.min(p.x, maxX) }),
        placeStations(R.map(R.prop('stationuuid'), channels), layout, {
          width: CELL_WIDTH,
          height: CELL_HEIGHT,
          columns: Math.max(1, Math.floor(width / CELL_WIDTH)),
        })
      )
    : {}

  const move =
    (uuid: string) =>
    ({ x, y }: Position) => {
      const next = {
        ...positions,
        [uuid]: {
          x: snap(x),
          y: snap(y),
          z: highest('z', Object.values(positions)) + 1,
        },
      }
      saveLayout(next)
      setLayout(next)
    }

  const height =
    highest('y', Object.values(positions)) + CELL_HEIGHT * SPARE_ROWS

  return { containerRef, positions, move, height }
}

export default useFavLayout
