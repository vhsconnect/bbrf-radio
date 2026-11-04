import * as R from 'ramda'
import { Option, Schema } from 'effect'

const STORAGE_KEY = 'bbrf-fav-layout'

const PositionSchema = Schema.Struct({ x: Schema.Number, y: Schema.Number })

const PlacementSchema = Schema.Struct({
  ...PositionSchema.fields,
  z: Schema.optionalWith(Schema.Number, { default: () => 0 }),
})

const FavLayoutSchema = Schema.Record({
  key: Schema.String,
  value: PlacementSchema,
})

export type Position = typeof PositionSchema.Type
export type Placement = typeof PlacementSchema.Type
export type FavLayout = typeof FavLayoutSchema.Type

export const loadLayout = (): FavLayout => {
  try {
    return Option.getOrElse(
      Schema.decodeUnknownOption(FavLayoutSchema)(
        JSON.parse(localStorage.getItem(STORAGE_KEY) ?? '{}')
      ),
      () => ({})
    )
  } catch {
    return {}
  }
}

export const saveLayout = (layout: FavLayout): void => {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(layout))
}

type Cell = { width: number; height: number; columns: number }

export const placeStations = (
  uuids: string[],
  layout: FavLayout,
  { width, height, columns }: Cell
): FavLayout => {
  const stored = R.pick(uuids, layout)
  const unplaced = R.reject(uuid => uuid in stored, uuids)
  const top = R.reduce(
    R.max<number>,
    0,
    R.map(R.prop('z'), Object.values(stored))
  )

  const cellAt = (index: number): Placement => ({
    x: (index % columns) * width,
    y: Math.floor(index / columns) * height,
    z: top + 1,
  })

  return {
    ...stored,
    ...R.zipObj(unplaced, R.times(cellAt, unplaced.length)),
  }
}
